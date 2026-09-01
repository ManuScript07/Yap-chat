-- Server-side user blocks. A row means that blocker_user_id has blocked
-- blocked_user_id. The blocked user must not learn more than the explicitly
-- allowed redacted identity through any public RPC or Storage path.
create table public.user_blocks (
  blocker_user_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

create index user_blocks_blocked_user_id_idx
  on public.user_blocks (blocked_user_id, blocker_user_id);

alter table public.user_blocks enable row level security;
revoke all on table public.user_blocks from public, anon, authenticated;
grant select, insert, delete on table public.user_blocks to authenticated, service_role;

create policy "Users manage their own block list"
on public.user_blocks
for all
to authenticated
using (blocker_user_id = (select auth.uid()))
with check (blocker_user_id = (select auth.uid()));

create or replace function private.is_blocked_by_impl(
  target_blocker_id uuid,
  target_blocked_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select target_blocker_id is not null
    and target_blocked_id is not null
    and exists (
      select 1
      from public.user_blocks block
      where block.blocker_user_id = target_blocker_id
        and block.blocked_user_id = target_blocked_id
    );
$$;

create or replace function private.is_user_pair_blocked_impl(
  first_user_id uuid,
  second_user_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.user_blocks block
    where (block.blocker_user_id = first_user_id and block.blocked_user_id = second_user_id)
       or (block.blocker_user_id = second_user_id and block.blocked_user_id = first_user_id)
  );
$$;

create or replace function private.is_conversation_blocked_impl(
  target_conversation_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members self_member
    join public.conversation_members peer_member
      on peer_member.conversation_id = self_member.conversation_id
     and peer_member.user_id <> self_member.user_id
    where self_member.conversation_id = target_conversation_id
      and self_member.user_id = auth.uid()
      and private.is_user_pair_blocked_impl(self_member.user_id, peer_member.user_id)
  );
$$;

revoke all on function private.is_blocked_by_impl(uuid, uuid) from public, anon;
revoke all on function private.is_user_pair_blocked_impl(uuid, uuid) from public, anon;
revoke all on function private.is_conversation_blocked_impl(uuid) from public, anon;
grant execute on function private.is_blocked_by_impl(uuid, uuid) to authenticated, service_role;
grant execute on function private.is_user_pair_blocked_impl(uuid, uuid) to authenticated, service_role;
grant execute on function private.is_conversation_blocked_impl(uuid) to authenticated, service_role;

create or replace function public.get_blocked_users()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language sql stable security invoker set search_path = ''
as $$
  select profile.id, profile.username, profile.display_name,
    profile.avatar_url, profile.avatar_storage_path, block.created_at
  from public.user_blocks block
  join public.profiles profile on profile.id = block.blocked_user_id
  where block.blocker_user_id = auth.uid()
  order by block.created_at desc, profile.id;
$$;

create or replace function private.broadcast_block_change_impl(
  first_user_id uuid,
  second_user_id uuid,
  action text
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare conversation_id uuid;
begin
  -- These are cache invalidation events, not user-visible notifications.
  perform realtime.send(jsonb_build_object('reason', 'block', 'action', action, 'profile_id', second_user_id), 'changed', 'user:' || first_user_id::text || ':friends', true);
  perform realtime.send(jsonb_build_object('reason', 'block', 'action', action, 'profile_id', first_user_id), 'changed', 'user:' || second_user_id::text || ':friends', true);
  select conversation.id into conversation_id
  from public.conversations conversation
  where conversation.user_one_id = least(first_user_id, second_user_id)
    and conversation.user_two_id = greatest(first_user_id, second_user_id);
  if conversation_id is not null then
    perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'block', 'action', action), 'changed', 'user:' || first_user_id::text || ':chats', true);
    perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'block', 'action', action), 'changed', 'user:' || second_user_id::text || ':chats', true);
  end if;
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

  insert into public.user_blocks (blocker_user_id, blocked_user_id)
  values (current_user_id, target_user_id)
  on conflict do nothing;

  delete from public.friendships
  where user_one_id = least(current_user_id, target_user_id)
    and user_two_id = greatest(current_user_id, target_user_id);
  delete from public.friend_requests
  where pair_user_one_id = least(current_user_id, target_user_id)
    and pair_user_two_id = greatest(current_user_id, target_user_id);

  perform private.broadcast_block_change_impl(current_user_id, target_user_id, 'blocked');
end;
$$;

create or replace function public.block_user(target_user_id uuid)
returns void
language sql security invoker set search_path = ''
as $$ select private.block_user_impl(target_user_id); $$;

create or replace function public.unblock_user(target_user_id uuid)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  delete from public.user_blocks
  where blocker_user_id = current_user_id and blocked_user_id = target_user_id;
  perform private.broadcast_block_change_impl(current_user_id, target_user_id, 'unblocked');
end;
$$;

revoke all on function private.broadcast_block_change_impl(uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.block_user_impl(uuid) from public, anon, authenticated;
grant execute on function private.block_user_impl(uuid) to authenticated, service_role;
grant execute on function public.get_blocked_users() to authenticated, service_role;
grant execute on function public.block_user(uuid) to authenticated, service_role;
grant execute on function public.unblock_user(uuid) to authenticated, service_role;

-- Direct avatar downloads previously bypassed profile RPC privacy completely.
drop policy if exists "Authenticated users can read avatars" on storage.objects;
create policy "Users can read non-blocked avatars"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and not exists (
    select 1
    from public.user_blocks block
    where block.blocker_user_id::text = (storage.foldername(name))[1]
      and block.blocked_user_id = (select auth.uid())
  )
);

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
  where not private.is_blocked_by_impl(profile.id, auth.uid());
$$;

-- A direct chat can never be created or used while either participant blocks
-- the other. Existing history remains readable.
create or replace function public.create_direct_conversation(peer_user_id uuid)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.create_direct_conversation_impl(peer_user_id);
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
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_conversation_blocked_impl(target_conversation_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.send_chat_message_impl(
    message_id, target_conversation_id, message_type, message_text,
    message_latitude, message_longitude, reply_message_id, message_attachments
  );
end;
$$;

-- Both direct and contact discovery hide a blocker from the blocked user.
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
  where not private.is_blocked_by_impl(candidate.id, auth.uid());
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
  where not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.match_new_friend_contact_phones(
  phone_numbers text[],
  friend_user_ids uuid[]
)
returns table (
  phone_number text, id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql stable security invoker set search_path = ''
as $$
  select candidate.*
  from private.match_new_friend_contact_phones_impl(phone_numbers, friend_user_ids) candidate
  where not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.send_friend_request(peer_user_id uuid)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  return private.send_friend_request_impl(peer_user_id);
end;
$$;

-- The profile RPC emits only the display name and an explicit relation marker
-- when the target has blocked the current viewer. Counting is intentionally
-- preserved, as requested.
create or replace function public.get_viewed_profile(
  target_user_id uuid,
  should_register_view boolean default true
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
  select friend.*
  from private.get_user_profile_friends_impl(target_user_id) friend
  where not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

create or replace function public.get_profile_view_count(target_user_id uuid)
returns bigint
language sql stable security invoker set search_path = ''
as $$
  select case
    when private.is_blocked_by_impl(target_user_id, auth.uid()) then 0
    else private.get_profile_view_count_impl(target_user_id)
  end;
$$;

create or replace function public.get_friend_location_visibility(friend_user_id uuid)
returns table (
  latitude double precision, longitude double precision, updated_at timestamptz, availability text
)
language sql security invoker set search_path = ''
as $$
  select *
  from private.get_friend_location_visibility_impl(friend_user_id)
  where not private.is_blocked_by_impl(friend_user_id, auth.uid());
$$;

create or replace function public.get_user_distance(target_user_id uuid)
returns table (distance_value integer, distance_unit text, updated_at timestamptz)
language sql security invoker set search_path = ''
as $$
  select *
  from private.get_user_distance_impl(target_user_id)
  where not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

create or replace function public.is_push_message_deliverable(
  target_message_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.messages message
    where message.id = target_message_id
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1
        from public.conversation_members peer
        where peer.conversation_id = message.conversation_id
          and peer.user_id <> message.sender_id
          and private.is_user_pair_blocked_impl(message.sender_id, peer.user_id)
      )
  );
$$;

-- Chat summaries drive the client cache. The flags are also used to turn
-- blocked sends into permanent local-only messages without a retry queue.
drop function if exists public.get_chat_summaries();
create function public.get_chat_summaries()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean
)
language sql stable security invoker set search_path = ''
as $$
  select summary.id, summary.peer_id,
    case when private.is_blocked_by_impl(summary.peer_id, auth.uid()) then '' else summary.peer_username end,
    summary.peer_display_name,
    case when private.is_blocked_by_impl(summary.peer_id, auth.uid()) then null else summary.peer_avatar_url end,
    case when private.is_blocked_by_impl(summary.peer_id, auth.uid()) then null else summary.peer_avatar_storage_path end,
    summary.last_message_id, summary.last_message_text, summary.last_message_type,
    summary.last_message_sender_id, summary.last_message_at, summary.unread_count,
    summary.is_muted,
    case when private.is_blocked_by_impl(summary.peer_id, auth.uid()) then null else summary.peer_last_seen_at end,
    case when private.is_blocked_by_impl(summary.peer_id, auth.uid()) then false else summary.peer_shows_last_seen end,
    private.is_blocked_by_impl(auth.uid(), summary.peer_id),
    private.is_blocked_by_impl(summary.peer_id, auth.uid())
  from private.get_chat_summaries_impl() summary;
$$;

grant execute on function public.create_direct_conversation(uuid) to authenticated, service_role;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb) to authenticated, service_role;
grant execute on function public.search_friend_candidates(text, integer) to authenticated, service_role;
grant execute on function public.match_contact_phones(text[]) to authenticated, service_role;
grant execute on function public.match_new_friend_contact_phones(text[], uuid[]) to authenticated, service_role;
grant execute on function public.send_friend_request(uuid) to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean) to authenticated, service_role;
grant execute on function public.get_user_profile_friends(uuid) to authenticated, service_role;
grant execute on function public.get_profile_view_count(uuid) to authenticated, service_role;
grant execute on function public.get_friend_location_visibility(uuid) to authenticated, service_role;
grant execute on function public.get_user_distance(uuid) to authenticated, service_role;
grant execute on function public.get_chat_summaries() to authenticated, service_role;
