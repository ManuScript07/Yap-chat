-- The clients keep durable caches and normally reconcile chats every twenty
-- seconds at most. These independent server-side quotas stop a modified client
-- from turning cache refreshes into an unbounded read loop, while remaining
-- deliberately above normal reconnect, pagination and realtime behaviour.

create table if not exists private.network_read_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_name text not null check (
    operation_name in (
      'chat_summaries',
      'conversation_messages',
      'friends',
      'friend_requests'
    )
  ),
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0),
  primary key (user_id, operation_name)
);

revoke all on table private.network_read_rate_limits
from public, anon, authenticated;

create table if not exists private.chat_message_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.chat_message_write_limits
from public, anon, authenticated;

create or replace function private.consume_network_read_quota(
  requested_operation text,
  request_limit integer
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

  if requested_operation not in (
    'chat_summaries',
    'conversation_messages',
    'friends',
    'friend_requests'
  ) or request_limit < 1 then
    raise exception using errcode = '22023', message = 'invalid_network_read_quota';
  end if;

  insert into private.network_read_rate_limits as limits (
    user_id, operation_name, window_started_at, request_count
  ) values (
    current_user_id, requested_operation, statement_timestamp(), 1
  )
  on conflict on constraint network_read_rate_limits_pkey do update
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
     or limits.request_count < request_limit
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'network_read_rate_limited';
  end if;
end;
$$;

create or replace function private.consume_chat_message_write_quota()
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

  -- 120 new messages per minute stays far above normal human typing while
  -- protecting the message table, attachment work and notification fan-out.
  insert into private.chat_message_write_limits as limits (
    user_id, window_started_at, request_count
  ) values (
    current_user_id, statement_timestamp(), 1
  )
  on conflict on constraint chat_message_write_limits_pkey do update
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
     or limits.request_count < 120
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'chat_message_rate_limited';
  end if;
end;
$$;

create or replace function private.get_chat_summaries_rate_limited_impl()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select summary.id, summary.peer_id,
    case when flags.redact then '' else summary.peer_username end,
    case when flags.globally_banned then 'Заблокированный пользователь'
      else summary.peer_display_name end,
    case when flags.redact then null else summary.peer_avatar_url end,
    case when flags.redact then null else summary.peer_avatar_storage_path end,
    summary.last_message_id, summary.last_message_text, summary.last_message_type,
    summary.last_message_sender_id, summary.last_message_at, summary.unread_count,
    summary.is_muted,
    case when flags.redact then null else summary.peer_last_seen_at end,
    case when flags.redact then false else summary.peer_shows_last_seen end,
    flags.blocked_by_me, flags.blocked_by_peer, flags.globally_banned
  from private.get_chat_summaries_impl() summary
  cross join lateral (
    select private.is_account_globally_banned(summary.peer_id) as globally_banned,
      private.is_blocked_by_impl(auth.uid(), summary.peer_id) as blocked_by_me,
      private.is_blocked_by_impl(summary.peer_id, auth.uid()) as blocked_by_peer
  ) flags_raw
  cross join lateral (
    select flags_raw.globally_banned, flags_raw.blocked_by_me, flags_raw.blocked_by_peer,
      (flags_raw.globally_banned or flags_raw.blocked_by_peer) as redact
  ) flags;
$$;

create or replace function public.get_chat_summaries()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('chat_summaries', 30);
  return query select * from private.get_chat_summaries_rate_limited_impl();
end;
$$;

alter function public.get_conversation_messages(uuid, timestamptz, uuid, integer)
  set schema private;

create function public.get_conversation_messages(
  target_conversation_id uuid,
  before_created_at timestamptz default null,
  before_message_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision, reply_to_message_id uuid,
  created_at timestamptz, read_at timestamptz, attachments jsonb,
  reply_sender_id uuid, reply_type text, reply_text text
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('conversation_messages', 60);
  return query
  select * from private.get_conversation_messages(
    target_conversation_id, before_created_at, before_message_id, page_size
  );
end;
$$;

create or replace function public.get_friends()
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friends', 30);
  return query
  select friend.id,
    case when flags.globally_banned then '' else friend.username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else friend.display_name end,
    case when flags.globally_banned then null else friend.avatar_url end,
    case when flags.globally_banned then null else friend.avatar_storage_path end,
    friend.friends_since
  from private.get_friends_impl() friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags;
end;
$$;

create or replace function public.get_friend_requests()
returns table (
  request_id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, peer_friend_count bigint,
  direction text, requested_at timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friend_requests', 30);
  return query
  select request.request_id, request.peer_id,
    case when flags.globally_banned then '' else request.peer_username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else request.peer_display_name end,
    case when flags.globally_banned then null else request.peer_avatar_url end,
    case when flags.globally_banned then null else request.peer_avatar_storage_path end,
    case when flags.globally_banned then null else request.peer_friend_count end,
    request.direction, request.requested_at
  from private.get_friend_requests_impl() request
  cross join lateral (
    select private.is_account_globally_banned(request.peer_id) as globally_banned
  ) flags;
end;
$$;

create or replace function public.send_chat_message(
  message_id uuid,
  target_conversation_id uuid,
  message_type text,
  message_text text default '',
  message_latitude double precision default null,
  message_longitude double precision default null,
  reply_message_id uuid default null,
  message_attachments jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  -- The sender retries an uncertain request with the same id. Do not charge
  -- such a retry against the write quota and preserve server idempotency.
  if exists (
    select 1
    from public.messages message
    where message.id = message_id
      and message.conversation_id = target_conversation_id
      and message.sender_id = auth.uid()
  ) then
    return message_id;
  end if;

  perform private.consume_chat_message_write_quota();

  peer_user_id := private.get_direct_conversation_peer_impl(
    target_conversation_id
  );

  if peer_user_id is null
     or private.is_account_globally_banned(peer_user_id)
     or private.is_conversation_blocked_impl(target_conversation_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.send_chat_message_impl(
    message_id, target_conversation_id, message_type, message_text,
    message_latitude, message_longitude, reply_message_id, message_attachments
  );
end;
$$;

revoke all on function private.consume_network_read_quota(text, integer)
from public, anon;
grant execute on function private.consume_network_read_quota(text, integer)
to authenticated, service_role;

revoke all on function private.consume_chat_message_write_quota()
from public, anon;
grant execute on function private.consume_chat_message_write_quota()
to authenticated, service_role;

revoke all on function private.get_chat_summaries_rate_limited_impl()
from public, anon;
grant execute on function private.get_chat_summaries_rate_limited_impl()
to authenticated, service_role;

revoke all on function private.get_conversation_messages(uuid, timestamptz, uuid, integer)
from public, anon;
grant execute on function private.get_conversation_messages(uuid, timestamptz, uuid, integer)
to authenticated, service_role;

revoke all on function public.get_chat_summaries() from public, anon;
revoke all on function public.get_conversation_messages(uuid, timestamptz, uuid, integer)
from public, anon;
revoke all on function public.get_friends() from public, anon;
revoke all on function public.get_friend_requests() from public, anon;
revoke all on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
from public, anon;
grant execute on function public.get_chat_summaries() to authenticated, service_role;
grant execute on function public.get_conversation_messages(uuid, timestamptz, uuid, integer)
to authenticated, service_role;
grant execute on function public.get_friends() to authenticated, service_role;
grant execute on function public.get_friend_requests() to authenticated, service_role;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
to authenticated, service_role;

notify pgrst, 'reload schema';
