alter table public.profiles
  add column show_friends_count boolean not null default true;

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references public.profiles(id) on delete cascade,
  user_two_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint friendships_distinct_users check (user_one_id <> user_two_id),
  constraint friendships_sorted_users check (user_one_id < user_two_id),
  constraint friendships_unique_pair unique (user_one_id, user_two_id)
);

create index friendships_user_two_created_idx
  on public.friendships (user_two_id, created_at desc);

create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  pair_user_one_id uuid generated always as (least(sender_id, recipient_id)) stored,
  pair_user_two_id uuid generated always as (greatest(sender_id, recipient_id)) stored,
  created_at timestamptz not null default now(),
  constraint friend_requests_distinct_users check (sender_id <> recipient_id),
  constraint friend_requests_unique_pair unique (pair_user_one_id, pair_user_two_id)
);

create index friend_requests_recipient_created_idx
  on public.friend_requests (recipient_id, created_at desc);
create index friend_requests_sender_created_idx
  on public.friend_requests (sender_id, created_at desc);

create table public.user_locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);

alter table public.friendships enable row level security;
alter table public.friend_requests enable row level security;
alter table public.user_locations enable row level security;

revoke all on public.friendships from public, anon, authenticated;
revoke all on public.friend_requests from public, anon, authenticated;
revoke all on public.user_locations from public, anon, authenticated;
grant select, insert, update, delete on public.friendships to service_role;
grant select, insert, update, delete on public.friend_requests to service_role;
grant select, insert, update, delete on public.user_locations to service_role;

create or replace function private.friend_count_visible_to(
  profile_id uuid,
  viewer_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select profile.show_friends_count or profile.id = viewer_id
    from public.profiles profile
    where profile.id = profile_id
  ), false);
$$;

create or replace function private.friend_count_for(profile_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)
  from public.friendships friendship
  where friendship.user_one_id = profile_id
     or friendship.user_two_id = profile_id;
$$;

create or replace function public.get_friends()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    friendship.created_at
  from public.friendships friendship
  join public.profiles peer
    on peer.id = case
      when friendship.user_one_id = auth.uid() then friendship.user_two_id
      else friendship.user_one_id
    end
  where auth.uid() is not null
    and auth.uid() in (friendship.user_one_id, friendship.user_two_id)
  order by friendship.created_at desc, friendship.id desc;
$$;

create or replace function public.get_friend_requests()
returns table (
  request_id uuid,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  peer_avatar_storage_path text,
  peer_friend_count bigint,
  direction text,
  requested_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    request.id,
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    case
      when private.friend_count_visible_to(peer.id, auth.uid())
        then private.friend_count_for(peer.id)
      else null
    end,
    case when request.sender_id = auth.uid() then 'outgoing' else 'incoming' end,
    request.created_at
  from public.friend_requests request
  join public.profiles peer
    on peer.id = case
      when request.sender_id = auth.uid() then request.recipient_id
      else request.sender_id
    end
  where auth.uid() is not null
    and auth.uid() in (request.sender_id, request.recipient_id)
  order by request.created_at desc, request.id desc;
$$;

create or replace function public.search_friend_candidates(
  search_query text,
  result_limit integer default 50
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security definer
set search_path = ''
as $$
  with normalized as (
    select lower(trim(coalesce(search_query, ''))) as query
  )
  select
    profile.id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when private.friend_count_visible_to(profile.id, auth.uid())
        then private.friend_count_for(profile.id)
      else null
    end,
    case
      when friendship.id is not null then 'friend'
      when request.sender_id = auth.uid() then 'outgoing'
      when request.recipient_id = auth.uid() then 'incoming'
      else 'none'
    end
  from public.profiles profile
  cross join normalized
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, auth.uid())
   and friendship.user_two_id = greatest(profile.id, auth.uid())
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, auth.uid())
   and request.pair_user_two_id = greatest(profile.id, auth.uid())
  where auth.uid() is not null
    and profile.id <> auth.uid()
    and normalized.query <> ''
    and (
      strpos(lower(profile.username), normalized.query) > 0
      or strpos(lower(profile.display_name), normalized.query) > 0
    )
  order by
    (lower(profile.username) = normalized.query) desc,
    (left(lower(profile.username), length(normalized.query)) = normalized.query) desc,
    lower(profile.display_name),
    profile.id
  limit least(greatest(coalesce(result_limit, 50), 1), 50);
$$;

create or replace function public.send_friend_request(peer_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  created_request_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication_required';
  end if;
  if peer_user_id is null or peer_user_id = current_user_id then
    raise exception 'invalid_friend_request';
  end if;
  if not exists (
    select 1 from public.profiles profile where profile.id = peer_user_id
  ) then
    raise exception 'profile_not_found';
  end if;
  if exists (
    select 1
    from public.friendships friendship
    where friendship.user_one_id = least(current_user_id, peer_user_id)
      and friendship.user_two_id = greatest(current_user_id, peer_user_id)
  ) then
    raise exception 'already_friends';
  end if;

  insert into public.friend_requests (sender_id, recipient_id)
  values (current_user_id, peer_user_id)
  returning id into created_request_id;

  return created_request_id;
exception
  when unique_violation then
    raise exception 'friend_request_already_exists';
end;
$$;

create or replace function public.cancel_friend_request(target_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.friend_requests request
  where request.id = target_request_id
    and request.sender_id = auth.uid();

  if not found then
    raise exception 'friend_request_not_found';
  end if;
end;
$$;

create or replace function public.respond_friend_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.friend_requests%rowtype;
begin
  select * into pending_request
  from public.friend_requests request
  where request.id = target_request_id
    and request.recipient_id = auth.uid()
  for update;

  if not found then
    raise exception 'friend_request_not_found';
  end if;

  if accept_request then
    insert into public.friendships (user_one_id, user_two_id)
    values (
      least(pending_request.sender_id, pending_request.recipient_id),
      greatest(pending_request.sender_id, pending_request.recipient_id)
    )
    on conflict (user_one_id, user_two_id) do nothing;
  end if;

  delete from public.friend_requests request
  where request.id = pending_request.id;
end;
$$;

create or replace function public.set_friends_count_visibility(is_visible boolean)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
  set show_friends_count = is_visible
  where id = auth.uid();
$$;

create or replace function public.update_my_location(
  new_latitude double precision,
  new_longitude double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;
  if new_latitude not between -90 and 90
     or new_longitude not between -180 and 180 then
    raise exception 'invalid_location';
  end if;

  insert into public.user_locations (user_id, latitude, longitude, updated_at)
  values (auth.uid(), new_latitude, new_longitude, now())
  on conflict (user_id) do update
  set latitude = excluded.latitude,
      longitude = excluded.longitude,
      updated_at = excluded.updated_at;
end;
$$;

create or replace function public.get_friend_location(friend_user_id uuid)
returns table (latitude double precision, longitude double precision, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select location.latitude, location.longitude, location.updated_at
  from public.user_locations location
  where location.user_id = friend_user_id
    and exists (
      select 1
      from public.friendships friendship
      where friendship.user_one_id = least(auth.uid(), friend_user_id)
        and friendship.user_two_id = greatest(auth.uid(), friend_user_id)
    );
$$;

create or replace function private.capture_message_sender_location()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'location' and new.latitude is not null and new.longitude is not null then
    insert into public.user_locations (user_id, latitude, longitude, updated_at)
    values (new.sender_id, new.latitude, new.longitude, new.created_at)
    on conflict (user_id) do update
    set latitude = excluded.latitude,
        longitude = excluded.longitude,
        updated_at = excluded.updated_at
    where public.user_locations.updated_at <= excluded.updated_at;
  end if;
  return new;
end;
$$;

create trigger messages_capture_sender_location
after insert on public.messages
for each row execute function private.capture_message_sender_location();

create or replace function private.broadcast_friend_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  first_user_id uuid;
  second_user_id uuid;
begin
  if tg_table_name = 'friendships' and tg_op = 'DELETE' then
    first_user_id := old.user_one_id;
    second_user_id := old.user_two_id;
  elsif tg_table_name = 'friendships' then
    first_user_id := new.user_one_id;
    second_user_id := new.user_two_id;
  elsif tg_op = 'DELETE' then
    first_user_id := old.sender_id;
    second_user_id := old.recipient_id;
  else
    first_user_id := new.sender_id;
    second_user_id := new.recipient_id;
  end if;

  perform realtime.send(
    jsonb_build_object('table', tg_table_name, 'operation', tg_op),
    'changed',
    'user:' || first_user_id::text || ':friends',
    true
  );
  perform realtime.send(
    jsonb_build_object('table', tg_table_name, 'operation', tg_op),
    'changed',
    'user:' || second_user_id::text || ':friends',
    true
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger friendships_broadcast_change
after insert or delete on public.friendships
for each row execute function private.broadcast_friend_change();
create trigger friend_requests_broadcast_change
after insert or delete on public.friend_requests
for each row execute function private.broadcast_friend_change();

drop policy if exists "Members can receive conversation broadcasts"
on realtime.messages;
create policy "Members can receive conversation broadcasts"
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (
    (select realtime.topic()) = 'user:' || (select auth.uid())::text || ':chats'
    or (select realtime.topic()) = 'user:' || (select auth.uid())::text || ':friends'
    or exists (
      select 1
      from public.conversation_members member
      where member.user_id = (select auth.uid())
        and (select realtime.topic()) = 'chat:' || member.conversation_id::text
    )
  )
);

revoke all on function private.friend_count_visible_to(uuid, uuid) from public, anon, authenticated;
revoke all on function private.friend_count_for(uuid) from public, anon, authenticated;
revoke all on function private.capture_message_sender_location() from public, anon, authenticated;
revoke all on function private.broadcast_friend_change() from public, anon, authenticated;

revoke all on function public.get_friends() from public, anon;
revoke all on function public.get_friend_requests() from public, anon;
revoke all on function public.search_friend_candidates(text, integer) from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.cancel_friend_request(uuid) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.set_friends_count_visibility(boolean) from public, anon;
revoke all on function public.update_my_location(double precision, double precision) from public, anon;
revoke all on function public.get_friend_location(uuid) from public, anon;

grant execute on function public.get_friends() to authenticated, service_role;
grant execute on function public.get_friend_requests() to authenticated, service_role;
grant execute on function public.search_friend_candidates(text, integer) to authenticated, service_role;
grant execute on function public.send_friend_request(uuid) to authenticated, service_role;
grant execute on function public.cancel_friend_request(uuid) to authenticated, service_role;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated, service_role;
grant execute on function public.set_friends_count_visibility(boolean) to authenticated, service_role;
grant execute on function public.update_my_location(double precision, double precision) to authenticated, service_role;
grant execute on function public.get_friend_location(uuid) to authenticated, service_role;

alter table public.push_notification_outbox
  alter column message_id drop not null,
  alter column conversation_id drop not null,
  add column notification_type text not null default 'chat_message'
    check (notification_type in ('chat_message', 'friend_request')),
  add column friend_request_id uuid references public.friend_requests(id) on delete cascade,
  add constraint push_notification_outbox_payload_check check (
    (notification_type = 'chat_message' and message_id is not null and conversation_id is not null and friend_request_id is null)
    or
    (notification_type = 'friend_request' and message_id is null and conversation_id is null and friend_request_id is not null)
  );

create unique index push_notification_outbox_friend_request_unique
  on public.push_notification_outbox (friend_request_id, recipient_user_id)
  where friend_request_id is not null;

create or replace function private.enqueue_friend_request_push_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_notification_outbox (
    message_id,
    conversation_id,
    recipient_user_id,
    sender_id,
    sender_name,
    message_type,
    message_text,
    message_created_at,
    notification_type,
    friend_request_id
  )
  select
    null,
    null,
    new.recipient_id,
    new.sender_id,
    sender.display_name,
    'text',
    '',
    new.created_at,
    'friend_request',
    new.id
  from public.profiles sender
  where sender.id = new.sender_id
  on conflict (friend_request_id, recipient_user_id)
    where friend_request_id is not null do nothing;
  return new;
end;
$$;

revoke all on function private.enqueue_friend_request_push_notification()
  from public, anon, authenticated;

create trigger friend_requests_enqueue_push_notification
after insert on public.friend_requests
for each row execute function private.enqueue_friend_request_push_notification();

comment on column public.profiles.show_friends_count is
  'Privacy switch for exposing the accepted-friend count through friend RPCs.';
comment on table public.user_locations is
  'Latest user location. Explicit location messages populate it; future background updates use update_my_location().' ;
