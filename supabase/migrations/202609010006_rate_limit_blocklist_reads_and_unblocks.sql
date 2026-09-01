-- Blacklist reads are an authenticated convenience endpoint, not a source of
-- truth for access control. Limit the exposed RPC independently from the
-- server-side block checks embedded in profile, chat and search operations.
create table private.user_block_read_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0)
);

create table private.user_unblock_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.user_block_read_limits from public, anon, authenticated;
revoke all on table private.user_unblock_write_limits from public, anon, authenticated;

create or replace function private.consume_user_block_read_quota()
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  insert into private.user_block_read_limits as limits (
    user_id, window_started_at, request_count
  ) values (auth.uid(), now(), 1)
  on conflict on constraint user_block_read_limits_pkey do update set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  returning request_count into current_count;

  if current_count > 10 then
    raise exception using errcode = 'P0001', message = 'user_block_read_rate_limited';
  end if;
end;
$$;

create or replace function private.consume_user_unblock_write_quota()
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  insert into private.user_unblock_write_limits as limits (
    user_id, window_started_at, request_count
  ) values (auth.uid(), now(), 1)
  on conflict on constraint user_unblock_write_limits_pkey do update set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  returning request_count into current_count;

  if current_count > 10 then
    raise exception using errcode = 'P0001', message = 'user_unblock_rate_limited';
  end if;
end;
$$;

create or replace function private.get_blocked_users_impl()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  perform private.consume_user_block_read_quota();

  return query
  select profile.id, profile.username, profile.display_name,
    profile.avatar_url, profile.avatar_storage_path, block.created_at
  from public.user_blocks block
  join public.profiles profile on profile.id = block.blocked_user_id
  where block.blocker_user_id = auth.uid()
  order by block.created_at desc, profile.id;
end;
$$;

create or replace function public.get_blocked_users()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language sql security invoker set search_path = ''
as $$
  select * from private.get_blocked_users_impl();
$$;

create or replace function private.unblock_user_impl(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_block_target';
  end if;

  perform private.lock_user_block_pair(current_user_id, target_user_id);

  delete from public.user_blocks
  where blocker_user_id = current_user_id and blocked_user_id = target_user_id;

  if found then
    perform private.consume_user_unblock_write_quota();
    perform private.broadcast_block_change_impl(
      current_user_id,
      target_user_id,
      'unblocked'
    );
  end if;
end;
$$;

revoke all on function private.consume_user_block_read_quota()
  from public, anon, authenticated;
revoke all on function private.consume_user_unblock_write_quota()
  from public, anon, authenticated;
revoke all on function private.get_blocked_users_impl()
  from public, anon, authenticated;
revoke all on function private.unblock_user_impl(uuid)
  from public, anon, authenticated;
grant execute on function private.consume_user_block_read_quota()
  to authenticated, service_role;
grant execute on function private.consume_user_unblock_write_quota()
  to authenticated, service_role;
grant execute on function private.get_blocked_users_impl()
  to authenticated, service_role;
grant execute on function private.unblock_user_impl(uuid)
  to authenticated, service_role;
