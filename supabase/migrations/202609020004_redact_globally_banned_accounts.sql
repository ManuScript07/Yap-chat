-- Global account bans are account-level access restrictions.  This migration
-- additionally makes an active banned account invisible in discovery and
-- redacts its existing relationship/chat presentation for other users.  Each
-- wrapper uses the indexed account-link lookup already maintained by the ban
-- system; no polling or Realtime subscription is introduced.

create or replace function public.create_direct_conversation(peer_user_id uuid)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_account_globally_banned(peer_user_id)
     or private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.create_direct_conversation_impl(peer_user_id);
end;
$$;

create or replace function private.avatar_owner_is_globally_banned(
  avatar_owner_folder text
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when avatar_owner_folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then private.is_account_globally_banned(avatar_owner_folder::uuid)
    else false
  end;
$$;

drop policy if exists "Users can read non-blocked avatars" on storage.objects;
create policy "Users can read non-blocked avatars"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and not private.avatar_owner_blocks_current_viewer_impl(
    (storage.foldername(name))[1]
  )
  and not private.avatar_owner_is_globally_banned(
    (storage.foldername(name))[1]
  )
);

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
language plpgsql security invoker set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  select member.user_id into peer_user_id
  from public.conversation_members member
  where member.conversation_id = target_conversation_id
    and member.user_id <> auth.uid()
  limit 1;

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

create or replace function public.send_friend_request(peer_user_id uuid)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_account_globally_banned(peer_user_id)
     or private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  return private.send_friend_request_impl(peer_user_id);
end;
$$;

create or replace function public.respond_friend_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  select case when request.sender_id = auth.uid()
    then request.recipient_id else request.sender_id end
  into peer_user_id
  from public.friend_requests request
  where request.id = target_request_id
    and request.recipient_id = auth.uid();

  if peer_user_id is null then
    raise exception using errcode = 'P0001', message = 'friend_request_not_found';
  end if;
  if accept_request and private.is_account_globally_banned(peer_user_id) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  perform private.respond_friend_request_impl(target_request_id, accept_request);
end;
$$;

create or replace function private.get_public_profiles_impl()
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select profile.id, profile.username, profile.display_name, profile.birth_date,
    profile.avatar_url, profile.avatar_storage_path, profile.avatar_updated_at,
    profile.gender, profile.bio, profile.onboarding_completed, profile.created_at,
    profile.updated_at
  from public.profiles profile
  where not private.is_account_globally_banned(profile.id)
    and not private.is_blocked_by_impl(profile.id, auth.uid());
$$;

create or replace function public.search_friend_candidates(
  search_query text,
  result_limit integer default 10
)
returns table (
  id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql stable security invoker set search_path = ''
as $$
  select candidate.*
  from private.search_friend_candidates_impl(search_query, result_limit) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.match_contact_phones(phone_numbers text[])
returns table (
  phone_number text, id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql stable security invoker set search_path = ''
as $$
  select candidate.*
  from private.match_contact_phones_impl(phone_numbers) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.match_new_friend_contact_phones(
  phone_numbers text[], friend_user_ids uuid[]
)
returns table (
  phone_number text, id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql stable security invoker set search_path = ''
as $$
  select candidate.*
  from private.match_new_friend_contact_phones_impl(phone_numbers, friend_user_ids) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.get_viewed_profile(
  target_user_id uuid, should_register_view boolean default true
)
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  photos jsonb, relationship text, request_id uuid, friend_count bigint,
  friends_preview jsonb, profile_view_count bigint, last_seen_at timestamptz,
  shows_last_seen boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_account_globally_banned(target_user_id) then
    return query
    select profile.id, ''::text, 'Заблокированный пользователь'::text, null::date,
      null::text, null::text, null::timestamptz,
      ''::text, ''::text, true, null::timestamptz,
      '[]'::jsonb, 'blocked'::text, null::uuid, 0::bigint,
      '[]'::jsonb, 0::bigint, null::timestamptz, false
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;
  if private.is_blocked_by_impl(target_user_id, auth.uid()) then
    if coalesce(should_register_view, true) then
      perform private.record_profile_view_impl(target_user_id);
    else
      perform private.get_profile_view_count_impl(target_user_id);
    end if;
    return query
    select profile.id, ''::text, profile.display_name, null::date,
      null::text, null::text, null::timestamptz,
      ''::text, ''::text, true, null::timestamptz,
      '[]'::jsonb, 'blocked'::text, null::uuid, 0::bigint,
      '[]'::jsonb, 0::bigint, null::timestamptz, false
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;
  return query select * from private.get_viewed_profile_impl(target_user_id, should_register_view);
end;
$$;

create or replace function public.get_user_profile_friends(target_user_id uuid)
returns table (
  id uuid, username text, display_name text, avatar_url text, avatar_storage_path text
)
language sql stable security invoker set search_path = ''
as $$
  select friend.id,
    case when flags.globally_banned then '' else friend.username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else friend.display_name end,
    case when flags.globally_banned then null else friend.avatar_url end,
    case when flags.globally_banned then null else friend.avatar_storage_path end
  from private.get_user_profile_friends_impl(target_user_id) friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

create or replace function public.get_friends()
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz
)
language sql stable security invoker set search_path = ''
as $$
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
$$;

create or replace function public.get_friend_requests()
returns table (
  request_id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, peer_friend_count bigint,
  direction text, requested_at timestamptz
)
language sql stable security invoker set search_path = ''
as $$
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
$$;

create or replace function public.get_friend_location_visibility(friend_user_id uuid)
returns table (
  latitude double precision, longitude double precision, updated_at timestamptz, availability text
)
language sql security invoker set search_path = ''
as $$
  select * from private.get_friend_location_visibility_impl(friend_user_id)
  where not private.is_account_globally_banned(friend_user_id)
    and not private.is_blocked_by_impl(friend_user_id, auth.uid());
$$;

create or replace function public.get_user_distance(target_user_id uuid)
returns table (distance_value integer, distance_unit text, updated_at timestamptz)
language sql stable security invoker set search_path = ''
as $$
  select * from private.get_user_distance_impl(target_user_id)
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

create or replace function public.is_push_message_deliverable(target_message_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.messages message
    where message.id = target_message_id
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.conversation_members peer
        where peer.conversation_id = message.conversation_id
          and peer.user_id <> message.sender_id
          and (private.is_account_globally_banned(peer.user_id)
            or private.is_user_pair_blocked_impl(message.sender_id, peer.user_id))
      )
  );
$$;

drop function if exists public.get_chat_summaries();
create function public.get_chat_summaries()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean
)
language sql stable security invoker set search_path = ''
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

grant execute on function public.create_direct_conversation(uuid) to authenticated, service_role;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb) to authenticated, service_role;
grant execute on function public.send_friend_request(uuid) to authenticated, service_role;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated, service_role;
grant execute on function public.search_friend_candidates(text, integer) to authenticated, service_role;
grant execute on function public.match_contact_phones(text[]) to authenticated, service_role;
grant execute on function public.match_new_friend_contact_phones(text[], uuid[]) to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean) to authenticated, service_role;
grant execute on function public.get_user_profile_friends(uuid) to authenticated, service_role;
grant execute on function public.get_friends() to authenticated, service_role;
grant execute on function public.get_friend_requests() to authenticated, service_role;
grant execute on function public.get_friend_location_visibility(uuid) to authenticated, service_role;
grant execute on function public.get_user_distance(uuid) to authenticated, service_role;
grant execute on function public.is_push_message_deliverable(uuid) to authenticated, service_role;
grant execute on function public.get_chat_summaries() to authenticated, service_role;
revoke all on function private.avatar_owner_is_globally_banned(text) from public, anon;
grant execute on function private.avatar_owner_is_globally_banned(text) to authenticated, service_role;

revoke all on function public.create_direct_conversation(uuid) from public, anon;
revoke all on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb) from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.search_friend_candidates(text, integer) from public, anon;
revoke all on function public.match_contact_phones(text[]) from public, anon;
revoke all on function public.match_new_friend_contact_phones(text[], uuid[]) from public, anon;
revoke all on function public.get_viewed_profile(uuid, boolean) from public, anon;
revoke all on function public.get_user_profile_friends(uuid) from public, anon;
revoke all on function public.get_friends() from public, anon;
revoke all on function public.get_friend_requests() from public, anon;
revoke all on function public.get_friend_location_visibility(uuid) from public, anon;
revoke all on function public.get_user_distance(uuid) from public, anon;
revoke all on function public.is_push_message_deliverable(uuid) from public, anon;
revoke all on function public.get_chat_summaries() from public, anon;
