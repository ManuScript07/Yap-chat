-- Incremental list refresh. Legacy whole-list RPC and its quota stay unchanged.
create table private.chat_summary_refresh_quota (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null check (request_count > 0),
  requested_rows integer not null check (requested_rows > 0)
);
alter table private.chat_summary_refresh_quota enable row level security;
revoke all on private.chat_summary_refresh_quota from public, anon, authenticated;
grant all on private.chat_summary_refresh_quota to service_role;
create policy chat_summary_refresh_service_only
  on private.chat_summary_refresh_quota to service_role
  using (true) with check (true);

create or replace function private.get_chat_summaries_by_ids_impl(conversation_ids uuid[])
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_deleted boolean, peer_is_online boolean
)
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  row_cost integer;
  quota_accepted integer;
begin
  if actor is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  perform private.require_active_account();
  if coalesce(cardinality(conversation_ids), 0) not between 1 and 50
     or array_ndims(conversation_ids) <> 1
     or array_position(conversation_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_chat_summary_selection';
  end if;
  select count(distinct requested_id)::integer into row_cost
  from unnest(conversation_ids) requested(requested_id);

  -- Shared across devices and function instances. Bound both calls and rows:
  -- small realtime batches must not compete with whole-list reconciliation.
  insert into private.chat_summary_refresh_quota as quota
    (user_id, window_started_at, request_count, requested_rows)
  values (actor, statement_timestamp(), 1, row_cost)
  on conflict (user_id) do update set
    window_started_at = case when quota.window_started_at <= statement_timestamp() - interval '1 minute'
      then statement_timestamp() else quota.window_started_at end,
    request_count = case when quota.window_started_at <= statement_timestamp() - interval '1 minute'
      then 1 else quota.request_count + 1 end,
    requested_rows = case when quota.window_started_at <= statement_timestamp() - interval '1 minute'
      then row_cost else quota.requested_rows + row_cost end
  where quota.window_started_at <= statement_timestamp() - interval '1 minute'
     or (quota.request_count < 180 and quota.requested_rows + row_cost <= 3000)
  returning request_count into quota_accepted;
  if quota_accepted is null then
    raise exception using errcode = 'PT429', message = 'chat_summary_refresh_rate_limited';
  end if;

  return query
  -- Authorization and requested IDs are applied BEFORE history/unread work.
  with visible_members as materialized (
    select member.conversation_id, member.cleared_at, member.is_muted
    from public.conversation_members member
    where member.user_id = actor and member.hidden_at is null
      and member.conversation_id = any(conversation_ids)
  )
  select conversation.id, peer.id,
    case when flags.redact then '' else peer.username end,
    case when flags.globally_banned then 'Заблокированный пользователь'
         when flags.pending_deletion then 'Удалённый пользователь'
         else peer.display_name end,
    case when flags.redact then null else peer.avatar_url end,
    case when flags.redact then null else peer.avatar_storage_path end,
    latest_message.id, latest_message.text, latest_message.type,
    latest_message.sender_id,
    coalesce(latest_message.created_at, conversation.created_at),
    (select count(*) from public.messages unread_message
      where unread_message.conversation_id = member.conversation_id
        and unread_message.sender_id <> actor
        and unread_message.deleted_for_everyone_at is null
        and unread_message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
        and not exists (select 1 from public.message_hidden_for_users hidden
          where hidden.message_id = unread_message.id and hidden.user_id = actor)
        -- Keep the unique (message,user) existence probe parameterized. A generic
        -- anti-join otherwise scanned ALL user receipts once per selected chat.
        and not coalesce((select true from public.message_receipts receipt
          where receipt.message_id = unread_message.id and receipt.user_id = actor
          limit 1), false)),
    member.is_muted,
    case when not flags.redact and seen.visible then peer.last_seen_at else null end,
    not flags.redact and seen.visible,
    flags.blocked_by_me, flags.blocked_by_peer, flags.globally_banned,
    flags.pending_deletion,
    not flags.redact and private.is_user_online(peer.id)
  from visible_members member
  join public.conversations conversation on conversation.id = member.conversation_id
  join public.profiles peer on peer.id = case when conversation.user_one_id = actor
    then conversation.user_two_id else conversation.user_one_id end
  left join private.search_privacy_settings privacy on privacy.user_id = peer.id
  left join public.friendships friendship
    on friendship.user_one_id = least(peer.id, actor)
   and friendship.user_two_id = greatest(peer.id, actor)
  left join lateral (
    select message.id, message.text, message.type, message.sender_id, message.created_at
    from public.messages message
    where message.conversation_id = member.conversation_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = actor)
    order by message.created_at desc, message.id desc limit 1
  ) latest_message on true
  cross join lateral (
    select private.is_account_globally_banned(peer.id) as globally_banned,
      private.is_account_pending_deletion(peer.id) as pending_deletion,
      private.is_blocked_by_impl(actor, peer.id) as blocked_by_me,
      private.is_blocked_by_impl(peer.id, actor) as blocked_by_peer
  ) flags_raw
  cross join lateral (
    select flags_raw.*,
      (flags_raw.globally_banned or flags_raw.pending_deletion or flags_raw.blocked_by_peer) as redact
  ) flags
  cross join lateral (
    select coalesce(privacy.last_seen_visibility, 'all') = 'all'
      or (coalesce(privacy.last_seen_visibility, 'all') = 'friends' and friendship.id is not null) as visible
  ) seen
  order by coalesce(latest_message.created_at, conversation.created_at) desc, conversation.id desc;
end;
$$;

create or replace function public.get_chat_summaries_by_ids(conversation_ids uuid[])
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_deleted boolean, peer_is_online boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.get_chat_summaries_by_ids_impl(conversation_ids); $$;

revoke all on function private.get_chat_summaries_by_ids_impl(uuid[]) from public, anon;
revoke all on function public.get_chat_summaries_by_ids(uuid[]) from public, anon;
grant execute on function private.get_chat_summaries_by_ids_impl(uuid[]) to authenticated, service_role;
grant execute on function public.get_chat_summaries_by_ids(uuid[]) to authenticated, service_role;
