-- A client-side in-flight guard is convenient, but cannot protect the RPC
-- endpoint from a modified client. Count only successful *new* blocks and
-- serialize every operation for a user pair on the server.
create table private.user_block_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.user_block_write_limits from public, anon, authenticated;

create or replace function private.consume_user_block_write_quota()
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  insert into private.user_block_write_limits as limits (
    user_id, window_started_at, request_count
  ) values (auth.uid(), now(), 1)
  on conflict on constraint user_block_write_limits_pkey do update set
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
    raise exception using errcode = 'P0001', message = 'user_block_rate_limited';
  end if;
end;
$$;

create or replace function private.lock_user_block_pair(
  first_user_id uuid,
  second_user_id uuid
)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      least(first_user_id, second_user_id)::text || ':' ||
          greatest(first_user_id, second_user_id)::text,
      0
    )
  );
end;
$$;

create or replace function private.block_user_impl(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_block_target';
  end if;
  if not exists (select 1 from public.profiles where id = target_user_id) then
    raise exception using errcode = '22023', message = 'profile_not_found';
  end if;

  perform private.lock_user_block_pair(current_user_id, target_user_id);

  if not exists (
    select 1 from public.user_blocks block
    where block.blocker_user_id = current_user_id
      and block.blocked_user_id = target_user_id
  ) then
    perform private.consume_user_block_write_quota();
    insert into public.user_blocks (blocker_user_id, blocked_user_id)
    values (current_user_id, target_user_id);
  end if;

  delete from public.friendships
  where user_one_id = least(current_user_id, target_user_id)
    and user_two_id = greatest(current_user_id, target_user_id);
  delete from public.friend_requests
  where pair_user_one_id = least(current_user_id, target_user_id)
    and pair_user_two_id = greatest(current_user_id, target_user_id);
end;
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
    perform private.broadcast_block_change_impl(
      current_user_id,
      target_user_id,
      'unblocked'
    );
  end if;
end;
$$;

revoke all on function private.consume_user_block_write_quota()
  from public, anon, authenticated;
revoke all on function private.lock_user_block_pair(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.block_user_impl(uuid)
  from public, anon, authenticated;
revoke all on function private.unblock_user_impl(uuid)
  from public, anon, authenticated;
grant execute on function private.consume_user_block_write_quota()
  to authenticated, service_role;
grant execute on function private.lock_user_block_pair(uuid, uuid)
  to authenticated, service_role;
grant execute on function private.block_user_impl(uuid)
  to authenticated, service_role;
grant execute on function private.unblock_user_impl(uuid)
  to authenticated, service_role;
