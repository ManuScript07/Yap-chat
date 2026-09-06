-- Server-managed, audience-scoped online presence. Clients keep one app
-- session lease and receive changes through their existing private user topic.
create extension if not exists pg_cron with schema pg_catalog;

create table private.user_presence_sessions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null,
  heartbeat_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  primary key (user_id, session_id)
);

create index user_presence_sessions_expiry_idx
  on private.user_presence_sessions (expires_at, user_id);

create table private.user_presence_watch_targets (
  watcher_user_id uuid not null,
  session_id uuid not null,
  scope_key text not null,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  primary key (watcher_user_id, session_id, scope_key, target_user_id),
  foreign key (watcher_user_id, session_id)
    references private.user_presence_sessions(user_id, session_id)
    on delete cascade,
  check (watcher_user_id <> target_user_id),
  check (char_length(scope_key) between 1 and 100)
);

create index user_presence_watch_targets_target_idx
  on private.user_presence_watch_targets (target_user_id, expires_at, watcher_user_id);

create table private.presence_write_limits (
  user_id uuid not null references public.profiles(id) on delete cascade,
  operation_key text not null,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, operation_key)
);

revoke all on table private.user_presence_sessions
  from public, anon, authenticated;
revoke all on table private.user_presence_watch_targets
  from public, anon, authenticated;
revoke all on table private.presence_write_limits
  from public, anon, authenticated;

create or replace function private.consume_presence_write_quota(
  operation_key text,
  maximum_requests integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.presence_write_limits as limits (
    user_id, operation_key, window_started_at, request_count
  ) values (
    current_user_id, operation_key, statement_timestamp(), 1
  )
  on conflict on constraint presence_write_limits_pkey do update
  set
    window_started_at = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then statement_timestamp()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then 1
      else limits.request_count + 1
    end
  where limits.window_started_at <= statement_timestamp() - interval '1 minute'
     or limits.request_count < maximum_requests
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'presence_rate_limited';
  end if;
end;
$$;

create or replace function private.is_user_online(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select $1 is not null
    and not private.is_account_globally_banned($1)
    and exists (
      select 1
      from private.user_presence_sessions session
      where session.user_id = $1
        and session.expires_at > statement_timestamp()
    );
$$;

create or replace function private.can_receive_user_presence(
  viewer_user_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select $1 is not null
    and $2 is not null
    and $1 <> $2
    and not private.is_account_globally_banned($1)
    and not private.is_account_globally_banned($2)
    and not private.is_blocked_by_impl($2, $1);
$$;

create or replace function private.send_presence_change_to_user(
  recipient_user_id uuid,
  target_user_id uuid,
  target_is_online boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if recipient_user_id is null
     or target_user_id is null
     or recipient_user_id = target_user_id
     or private.is_account_globally_banned(recipient_user_id) then
    return;
  end if;
  perform realtime.send(
    jsonb_build_object(
      'user_id', target_user_id,
      'is_online', coalesce(target_is_online, false)
    ),
    'presence_changed',
    'user:' || recipient_user_id::text || ':chats',
    true
  );
end;
$$;

create or replace function private.broadcast_user_presence_change(
  p_target_user_id uuid,
  p_target_is_online boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient record;
begin
  if p_target_user_id is null then return; end if;

  for recipient in
    with audience as (
      select case
        when friendship.user_one_id = p_target_user_id
          then friendship.user_two_id
        else friendship.user_one_id
      end as user_id
      from public.friendships friendship
      where friendship.user_one_id = p_target_user_id
         or friendship.user_two_id = p_target_user_id

      union

      select peer.user_id
      from public.conversation_members self_member
      join public.conversation_members peer
        on peer.conversation_id = self_member.conversation_id
       and peer.user_id <> self_member.user_id
      where self_member.user_id = p_target_user_id
        and peer.hidden_at is null

      union

      select watch.watcher_user_id
      from private.user_presence_watch_targets watch
      where watch.target_user_id = p_target_user_id
        and watch.expires_at > statement_timestamp()
    )
    select distinct audience.user_id
    from audience
    where audience.user_id is not null
      and audience.user_id <> p_target_user_id
      and not private.is_account_globally_banned(audience.user_id)
      and (
        not coalesce(p_target_is_online, false)
        or private.can_receive_user_presence(audience.user_id, p_target_user_id)
      )
      and not private.is_blocked_by_impl(p_target_user_id, audience.user_id)
  loop
    perform private.send_presence_change_to_user(
      recipient.user_id,
      p_target_user_id,
      p_target_is_online
    );
  end loop;
end;
$$;

create or replace function private.touch_my_presence_session_impl(
  target_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  was_online boolean;
  affected_rows integer := 0;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if target_session_id is null then
    raise exception using errcode = '22023', message = 'invalid_presence_session';
  end if;
  if private.is_account_globally_banned(current_user_id) then
    raise exception using errcode = '42501', message = 'account_globally_banned';
  end if;

  perform private.consume_presence_write_quota('heartbeat', 10);
  perform pg_advisory_xact_lock(
    hashtextextended('presence:' || current_user_id::text, 0)
  );
  was_online := private.is_user_online(current_user_id);

  insert into private.user_presence_sessions as session (
    user_id, session_id, heartbeat_at, expires_at
  ) values (
    current_user_id,
    target_session_id,
    statement_timestamp(),
    statement_timestamp() + interval '75 seconds'
  )
  on conflict on constraint user_presence_sessions_pkey do update
  set heartbeat_at = excluded.heartbeat_at,
      expires_at = excluded.expires_at
  where session.heartbeat_at <= statement_timestamp() - interval '10 seconds';
  get diagnostics affected_rows = row_count;

  if affected_rows > 0 then
    update private.user_presence_watch_targets watch
    set expires_at = statement_timestamp() + interval '75 seconds'
    where watch.watcher_user_id = current_user_id
      and watch.session_id = target_session_id;

    update public.profiles
    set last_seen_at = statement_timestamp()
    where id = current_user_id;
  end if;

  delete from private.user_presence_sessions session
  where session.user_id = current_user_id
    and session.expires_at <= statement_timestamp();

  delete from private.user_presence_sessions session
  where session.user_id = current_user_id
    and session.session_id in (
      select extra.session_id
      from private.user_presence_sessions extra
      where extra.user_id = current_user_id
      order by extra.heartbeat_at desc, extra.session_id
      offset 10
    );

  if not was_online and private.is_user_online(current_user_id) then
    perform private.broadcast_user_presence_change(current_user_id, true);
  end if;
end;
$$;

create or replace function public.touch_my_presence_session(
  target_session_id uuid
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.touch_my_presence_session_impl(target_session_id);
$$;

create or replace function private.close_my_presence_session_impl(
  target_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  was_online boolean;
begin
  if current_user_id is null then return; end if;
  if target_session_id is null then return; end if;

  perform private.consume_presence_write_quota('close', 10);
  perform pg_advisory_xact_lock(
    hashtextextended('presence:' || current_user_id::text, 0)
  );
  was_online := private.is_user_online(current_user_id);

  delete from private.user_presence_sessions session
  where session.user_id = current_user_id
    and session.session_id = target_session_id;

  update public.profiles
  set last_seen_at = statement_timestamp()
  where id = current_user_id;

  if was_online and not private.is_user_online(current_user_id) then
    perform private.broadcast_user_presence_change(current_user_id, false);
  end if;
end;
$$;

create or replace function public.close_my_presence_session(
  target_session_id uuid
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.close_my_presence_session_impl(target_session_id);
$$;

create or replace function private.set_my_presence_watch_scope_impl(
  target_session_id uuid,
  scope_key text,
  target_user_ids uuid[]
)
returns table (target_user_id uuid, is_online boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_scope text := trim(coalesce(scope_key, ''));
  normalized_targets uuid[];
  allowed_targets uuid[];
  session_expiry timestamptz;
  existing_targets uuid[];
  resulting_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if target_session_id is null
     or normalized_scope !~ '^[A-Za-z0-9:_-]{1,100}$' then
    raise exception using errcode = '22023', message = 'invalid_presence_scope';
  end if;

  select array_agg(distinct requested order by requested)
  into normalized_targets
  from unnest(coalesce(target_user_ids, '{}'::uuid[])) requested
  where requested is not null and requested <> current_user_id;
  normalized_targets := coalesce(normalized_targets, '{}'::uuid[]);
  if cardinality(normalized_targets) > 100 then
    raise exception using errcode = '22023', message = 'presence_scope_too_large';
  end if;

  select session.expires_at
  into session_expiry
  from private.user_presence_sessions session
  where session.user_id = current_user_id
    and session.session_id = target_session_id
    and session.expires_at > statement_timestamp();
  if session_expiry is null then
    raise exception using errcode = '42501', message = 'presence_session_inactive';
  end if;

  perform private.consume_presence_write_quota('watch_scope', 30);
  perform pg_advisory_xact_lock(
    hashtextextended(
      'presence-watch:' || current_user_id::text || ':' || target_session_id::text,
      0
    )
  );

  select coalesce(array_agg(requested order by requested), '{}'::uuid[])
  into allowed_targets
  from unnest(normalized_targets) requested
  where private.can_receive_user_presence(current_user_id, requested);

  select coalesce(array_agg(watch.target_user_id order by watch.target_user_id), '{}'::uuid[])
  into existing_targets
  from private.user_presence_watch_targets watch
  where watch.watcher_user_id = current_user_id
    and watch.session_id = target_session_id
    and watch.scope_key = normalized_scope;

  if existing_targets is distinct from allowed_targets then
    delete from private.user_presence_watch_targets watch
    where watch.watcher_user_id = current_user_id
      and watch.session_id = target_session_id
      and watch.scope_key = normalized_scope;

    insert into private.user_presence_watch_targets (
      watcher_user_id, session_id, scope_key, target_user_id, expires_at
    )
    select current_user_id, target_session_id, normalized_scope,
      requested, session_expiry
    from unnest(allowed_targets) requested;
  end if;

  select count(*) into resulting_count
  from private.user_presence_watch_targets watch
  where watch.watcher_user_id = current_user_id
    and watch.session_id = target_session_id;
  if resulting_count > 250 then
    raise exception using errcode = '22023', message = 'presence_audience_too_large';
  end if;

  return query
  select requested,
    private.can_receive_user_presence(current_user_id, requested)
      and private.is_user_online(requested)
  from unnest(normalized_targets) requested;
end;
$$;

create or replace function public.set_my_presence_watch_scope(
  target_session_id uuid,
  scope_key text,
  target_user_ids uuid[]
)
returns table (target_user_id uuid, is_online boolean)
language sql
security invoker
set search_path = ''
as $$
  select *
  from private.set_my_presence_watch_scope_impl(
    target_session_id,
    scope_key,
    target_user_ids
  );
$$;

create or replace function private.expire_stale_presence_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_user record;
  expired_count integer := 0;
begin
  for expired_user in
    select distinct session.user_id
    from private.user_presence_sessions session
    where session.expires_at <= statement_timestamp()
      and not exists (
        select 1
        from private.user_presence_sessions active
        where active.user_id = session.user_id
          and active.expires_at > statement_timestamp()
      )
  loop
    perform pg_advisory_xact_lock(
      hashtextextended('presence:' || expired_user.user_id::text, 0)
    );
    if not exists (
      select 1 from private.user_presence_sessions active
      where active.user_id = expired_user.user_id
        and active.expires_at > statement_timestamp()
    ) then
      perform private.broadcast_user_presence_change(expired_user.user_id, false);
      delete from private.user_presence_sessions session
      where session.user_id = expired_user.user_id
        and session.expires_at <= statement_timestamp();
      expired_count := expired_count + 1;
    end if;
  end loop;

  delete from private.user_presence_sessions session
  where session.expires_at <= statement_timestamp();
  return expired_count;
end;
$$;

create or replace function private.hide_blocker_presence_after_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.send_presence_change_to_user(
    new.blocked_user_id,
    new.blocker_user_id,
    false
  );
  delete from private.user_presence_watch_targets watch
  where watch.watcher_user_id = new.blocked_user_id
    and watch.target_user_id = new.blocker_user_id;
  return new;
end;
$$;

create trigger user_blocks_hide_blocker_presence
after insert on public.user_blocks
for each row execute function private.hide_blocker_presence_after_block();

create or replace function private.force_linked_account_presence_offline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.is_account_globally_banned(new.user_id) then
    perform private.broadcast_user_presence_change(new.user_id, false);
    delete from private.user_presence_sessions session
    where session.user_id = new.user_id;
  end if;
  return new;
end;
$$;

create trigger global_ban_links_force_presence_offline
after insert or update on private.global_ban_account_links
for each row execute function private.force_linked_account_presence_offline();

-- The old global Presence room exposes every online id to every signed-in
-- account. No application code uses it after this migration.
drop policy if exists "Authenticated users can receive presence"
  on realtime.messages;
drop policy if exists "Authenticated users can track presence"
  on realtime.messages;

revoke all on function private.consume_presence_write_quota(text, integer)
  from public, anon, authenticated;
revoke all on function private.is_user_online(uuid)
  from public, anon;
revoke all on function private.can_receive_user_presence(uuid, uuid)
  from public, anon;
revoke all on function private.send_presence_change_to_user(uuid, uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.broadcast_user_presence_change(uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.touch_my_presence_session_impl(uuid)
  from public, anon;
revoke all on function private.close_my_presence_session_impl(uuid)
  from public, anon;
revoke all on function private.set_my_presence_watch_scope_impl(uuid, text, uuid[])
  from public, anon;
revoke all on function private.expire_stale_presence_sessions()
  from public, anon, authenticated;
revoke all on function private.hide_blocker_presence_after_block()
  from public, anon, authenticated;
revoke all on function private.force_linked_account_presence_offline()
  from public, anon, authenticated;
revoke all on function public.touch_my_presence_session(uuid)
  from public, anon;
revoke all on function public.close_my_presence_session(uuid)
  from public, anon;
revoke all on function public.set_my_presence_watch_scope(uuid, text, uuid[])
  from public, anon;

grant execute on function private.is_user_online(uuid)
  to authenticated, service_role;
grant execute on function private.can_receive_user_presence(uuid, uuid)
  to authenticated, service_role;
grant execute on function private.touch_my_presence_session_impl(uuid)
  to authenticated, service_role;
grant execute on function private.close_my_presence_session_impl(uuid)
  to authenticated, service_role;
grant execute on function private.set_my_presence_watch_scope_impl(uuid, text, uuid[])
  to authenticated, service_role;
grant execute on function public.touch_my_presence_session(uuid)
  to authenticated, service_role;
grant execute on function public.close_my_presence_session(uuid)
  to authenticated, service_role;
grant execute on function public.set_my_presence_watch_scope(uuid, text, uuid[])
  to authenticated, service_role;

do $$
begin
  if to_regclass('cron.job') is not null then
    execute $schedule$
      select cron.schedule(
        'expire-user-presence-sessions',
        '* * * * *',
        'select private.expire_stale_presence_sessions()'
      )
      where not exists (
        select 1 from cron.job
        where jobname = 'expire-user-presence-sessions'
      )
    $schedule$;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping presence expiry cron; schedule it with database owner privileges';
end;
$$;

notify pgrst, 'reload schema';
