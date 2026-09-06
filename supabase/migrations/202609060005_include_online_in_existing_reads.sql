-- Seed online state through RPCs the app already performs. The new boolean is
-- appended so every pre-existing column keeps its position and meaning.

drop function public.get_chat_summaries();
drop function private.get_chat_summaries_rate_limited_impl();

create function private.get_chat_summaries_rate_limited_impl()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_online boolean
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
    flags.blocked_by_me, flags.blocked_by_peer, flags.globally_banned,
    not flags.redact and private.is_user_online(summary.peer_id)
  from private.get_chat_summaries_impl() summary
  cross join lateral (
    select private.is_account_globally_banned(summary.peer_id) as globally_banned,
      private.is_blocked_by_impl(auth.uid(), summary.peer_id) as blocked_by_me,
      private.is_blocked_by_impl(summary.peer_id, auth.uid()) as blocked_by_peer
  ) flags_raw
  cross join lateral (
    select flags_raw.globally_banned, flags_raw.blocked_by_me,
      flags_raw.blocked_by_peer,
      (flags_raw.globally_banned or flags_raw.blocked_by_peer) as redact
  ) flags;
$$;

create function public.get_chat_summaries()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_online boolean
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

drop function public.get_friends();

create function public.get_friends()
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz, is_online boolean
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
    friend.friends_since,
    not flags.globally_banned and private.is_user_online(friend.id)
  from private.get_friends_impl() friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags;
end;
$$;

drop function public.get_viewed_profile(uuid, boolean);

create function public.get_viewed_profile(
  target_user_id uuid,
  should_register_view boolean default true
)
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  photos jsonb, relationship text, request_id uuid, friend_count bigint,
  friends_preview jsonb, profile_view_count bigint, last_seen_at timestamptz,
  shows_last_seen boolean, is_online boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_profile_read_quota(target_user_id);

  if private.is_account_globally_banned(target_user_id) then
    return query
    select profile.id, ''::text, 'Заблокированный пользователь'::text, null::date,
      null::text, null::text, null::timestamptz,
      ''::text, ''::text, true, null::timestamptz,
      '[]'::jsonb, 'blocked'::text, null::uuid, 0::bigint,
      '[]'::jsonb, 0::bigint, null::timestamptz, false, false
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
      '[]'::jsonb, 0::bigint, null::timestamptz, false, false
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;

  return query
  select profile.*, private.is_user_online(profile.id)
  from private.get_viewed_profile_impl(
    target_user_id,
    should_register_view
  ) profile;
end;
$$;

drop function public.get_nearby_people(text, integer, integer, uuid, integer);
drop function private.get_nearby_people_impl(text, integer, integer, uuid, integer);

create function private.get_nearby_people_impl(
  preferred_gender text default null,
  minimum_age integer default 18,
  maximum_age integer default 99,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  active_until timestamptz,
  has_more boolean,
  is_online boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_gender text := nullif(lower(trim(coalesce(preferred_gender, ''))), '');
  normalized_minimum_age integer := coalesce(minimum_age, 18);
  normalized_maximum_age integer := coalesce(maximum_age, 99);
  normalized_page_size integer := least(greatest(coalesce(page_size, 30), 1), 30);
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if normalized_gender is not null and normalized_gender not in ('male', 'female') then
    raise exception using errcode = '22023', message = 'invalid_nearby_gender';
  end if;
  if normalized_minimum_age < 18
     or normalized_maximum_age > 99
     or normalized_minimum_age > normalized_maximum_age then
    raise exception using errcode = '22023', message = 'invalid_nearby_age_range';
  end if;

  perform private.consume_nearby_people_read_quota();

  if not exists (
    select 1
    from public.user_locations own_location
    where own_location.user_id = current_user_id
      and own_location.updated_at > statement_timestamp() - interval '12 hours'
  ) then
    raise exception using errcode = 'P0001', message = 'nearby_location_required';
  end if;

  return query
  with own_location as (
    select location.geography
    from public.user_locations location
    where location.user_id = current_user_id
  ), cursor as (
    select extensions.st_distance(own.geography, location.geography) as distance_meters
    from own_location own
    join public.user_locations location on location.user_id = after_user_id
  ), candidates as materialized (
    select
      profile.id,
      profile.username,
      profile.display_name,
      profile.avatar_url,
      profile.avatar_storage_path,
      profile.last_seen_at + interval '3 days' as active_until,
      extensions.st_distance(own.geography, location.geography) as distance_meters
    from own_location own
    join public.user_locations location
      on extensions.st_dwithin(location.geography, own.geography, 100000.0)
    join public.profiles profile on profile.id = location.user_id
    where profile.id <> current_user_id
      and profile.onboarding_completed
      and profile.birth_date is not null
      and profile.last_seen_at > statement_timestamp() - interval '3 days'
      and date_part('year', age(current_date, profile.birth_date))
          between normalized_minimum_age and normalized_maximum_age
      and (normalized_gender is null or profile.gender = normalized_gender)
      and not private.is_user_pair_blocked_impl(current_user_id, profile.id)
      and not private.is_account_globally_banned(profile.id)
  ), ranked as materialized (
    select candidate.*
    from candidates candidate
    order by candidate.distance_meters, candidate.id
    limit 100
  ), limited as materialized (
    select candidate.*
    from ranked candidate
    left join cursor on true
    where after_user_id is null
       or cursor.distance_meters is null
       or candidate.distance_meters > cursor.distance_meters
       or (
         candidate.distance_meters = cursor.distance_meters
         and candidate.id > after_user_id
       )
    order by candidate.distance_meters, candidate.id
    limit normalized_page_size + 1
  ), page as materialized (
    select * from limited
    order by distance_meters, id
    limit normalized_page_size
  )
  select
    page.id,
    page.username,
    page.display_name,
    page.avatar_url,
    page.avatar_storage_path,
    page.active_until,
    exists (select 1 from limited offset normalized_page_size) as has_more,
    private.is_user_online(page.id)
  from page
  order by page.distance_meters, page.id;
end;
$$;

create function public.get_nearby_people(
  preferred_gender text default null,
  minimum_age integer default 18,
  maximum_age integer default 99,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  active_until timestamptz,
  has_more boolean,
  is_online boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from private.get_nearby_people_impl(
    preferred_gender,
    minimum_age,
    maximum_age,
    after_user_id,
    page_size
  );
$$;

revoke all on function private.get_chat_summaries_rate_limited_impl()
  from public, anon;
revoke all on function public.get_chat_summaries() from public, anon;
revoke all on function public.get_friends() from public, anon;
revoke all on function public.get_viewed_profile(uuid, boolean)
  from public, anon;
revoke all on function private.get_nearby_people_impl(text, integer, integer, uuid, integer)
  from public, anon;
revoke all on function public.get_nearby_people(text, integer, integer, uuid, integer)
  from public, anon;

grant execute on function private.get_chat_summaries_rate_limited_impl()
  to authenticated, service_role;
grant execute on function public.get_chat_summaries()
  to authenticated, service_role;
grant execute on function public.get_friends()
  to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean)
  to authenticated, service_role;
grant execute on function private.get_nearby_people_impl(text, integer, integer, uuid, integer)
  to authenticated, service_role;
grant execute on function public.get_nearby_people(text, integer, integer, uuid, integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';
