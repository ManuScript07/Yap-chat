-- Location visibility is account-scoped and deliberately lives next to the
-- other privacy preferences.  Recording a device location remains independent
-- from these flags: it is needed for future nearby-user ranking.
alter table private.search_privacy_settings
  add column if not exists share_precise_location boolean not null default true,
  add column if not exists share_distance boolean not null default true;

-- Preserve the only pre-existing location setting before retiring it.
insert into private.search_privacy_settings (
  user_id, share_precise_location, share_distance, updated_at
)
select profile.id, false, true, now()
from public.profiles profile
where not profile.share_location
on conflict (user_id) do update
  set share_precise_location = false,
      updated_at = excluded.updated_at;

-- The RPC settings snapshot is cached as one unit by the client. PostgreSQL
-- requires a drop before expanding a table-returning function's result type.
drop function public.get_my_search_privacy_settings();
drop function private.get_my_search_privacy_settings_impl();
drop function public.update_my_search_privacy_settings(boolean, boolean, boolean);
drop function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean);
drop function public.set_my_search_privacy_setting(text, boolean);
drop function private.set_my_search_privacy_setting_impl(text, boolean);
drop function public.set_my_last_seen_visibility(text);
drop function private.set_my_last_seen_visibility_impl(text);

create function private.get_my_search_privacy_settings_impl()
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean,
  last_seen_visibility text,
  share_precise_location boolean,
  share_distance boolean
)
language sql stable security definer set search_path = ''
as $$
  select coalesce(settings.search_by_username, true),
         coalesce(settings.search_by_phone, true),
         coalesce(settings.search_by_name, true),
         coalesce(settings.last_seen_visibility, 'all'),
         coalesce(settings.share_precise_location, true),
         coalesce(settings.share_distance, true)
  from (select auth.uid() as user_id) viewer
  left join private.search_privacy_settings settings on settings.user_id = viewer.user_id
  where viewer.user_id is not null;
$$;

create function private.set_my_search_privacy_setting_impl(
  setting_key text, is_enabled boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if setting_key not in ('username', 'phone', 'name') or is_enabled is null then
    raise exception using errcode = '22023', message = 'invalid_search_privacy_setting';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name,
    last_seen_visibility, share_precise_location, share_distance, updated_at
  ) values (
    auth.uid(),
    case when setting_key = 'username' then is_enabled else true end,
    case when setting_key = 'phone' then is_enabled else true end,
    case when setting_key = 'name' then is_enabled else true end,
    'all', true, true, now()
  ) on conflict (user_id) do update set
    search_by_username = case when setting_key = 'username' then is_enabled else settings.search_by_username end,
    search_by_phone = case when setting_key = 'phone' then is_enabled else settings.search_by_phone end,
    search_by_name = case when setting_key = 'name' then is_enabled else settings.search_by_name end,
    updated_at = now()
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility,
    settings.share_precise_location, settings.share_distance;
end;
$$;

create function private.update_my_search_privacy_settings_impl(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name,
    last_seen_visibility, share_precise_location, share_distance, updated_at
  ) values (
    auth.uid(), is_searchable_by_username, is_searchable_by_phone,
    is_searchable_by_name, 'all', true, true, now()
  ) on conflict (user_id) do update set
    search_by_username = excluded.search_by_username,
    search_by_phone = excluded.search_by_phone,
    search_by_name = excluded.search_by_name,
    updated_at = excluded.updated_at
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility,
    settings.share_precise_location, settings.share_distance;
end;
$$;

create function private.set_my_last_seen_visibility_impl(visibility text)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if visibility not in ('all', 'friends', 'nobody') then
    raise exception using errcode = '22023', message = 'invalid_last_seen_visibility';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name,
    last_seen_visibility, share_precise_location, share_distance, updated_at
  ) values (auth.uid(), true, true, true, visibility, true, true, now())
  on conflict (user_id) do update set
    last_seen_visibility = excluded.last_seen_visibility,
    updated_at = excluded.updated_at
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility,
    settings.share_precise_location, settings.share_distance;
  perform private.broadcast_last_seen_visibility_changed();
end;
$$;

create function private.set_my_location_visibility_impl(
  is_precise_location_shared boolean,
  is_distance_shared boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if is_precise_location_shared is null or is_distance_shared is null then
    raise exception using errcode = '22023', message = 'invalid_location_visibility';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name,
    last_seen_visibility, share_precise_location, share_distance, updated_at
  ) values (
    auth.uid(), true, true, true, 'all', is_precise_location_shared,
    is_distance_shared, now()
  ) on conflict (user_id) do update set
    share_precise_location = excluded.share_precise_location,
    share_distance = excluded.share_distance,
    updated_at = excluded.updated_at
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility,
    settings.share_precise_location, settings.share_distance;
end;
$$;

create function public.get_my_search_privacy_settings()
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.get_my_search_privacy_settings_impl(); $$;

create function public.set_my_search_privacy_setting(setting_key text, is_enabled boolean)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_search_privacy_setting_impl(setting_key, is_enabled); $$;

create function public.update_my_search_privacy_settings(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language sql security invoker set search_path = ''
as $$
  select * from private.update_my_search_privacy_settings_impl(
    is_searchable_by_username, is_searchable_by_phone, is_searchable_by_name
  );
$$;

create function public.set_my_last_seen_visibility(visibility text)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_last_seen_visibility_impl(visibility); $$;

create function public.set_my_location_visibility(
  is_precise_location_shared boolean,
  is_distance_shared boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean
)
language sql security invoker set search_path = ''
as $$
  select * from private.set_my_location_visibility_impl(
    is_precise_location_shared, is_distance_shared
  );
$$;

revoke all on function private.get_my_search_privacy_settings_impl() from public, anon;
revoke all on function private.set_my_search_privacy_setting_impl(text, boolean) from public, anon;
revoke all on function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean) from public, anon;
revoke all on function private.set_my_last_seen_visibility_impl(text) from public, anon;
revoke all on function private.set_my_location_visibility_impl(boolean, boolean) from public, anon;
grant execute on function private.get_my_search_privacy_settings_impl() to authenticated, service_role;
grant execute on function private.set_my_search_privacy_setting_impl(text, boolean) to authenticated, service_role;
grant execute on function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean) to authenticated, service_role;
grant execute on function private.set_my_last_seen_visibility_impl(text) to authenticated, service_role;
grant execute on function private.set_my_location_visibility_impl(boolean, boolean) to authenticated, service_role;
grant execute on function public.get_my_search_privacy_settings() to authenticated, service_role;
grant execute on function public.set_my_search_privacy_setting(text, boolean) to authenticated, service_role;
grant execute on function public.update_my_search_privacy_settings(boolean, boolean, boolean) to authenticated, service_role;
grant execute on function public.set_my_last_seen_visibility(text) to authenticated, service_role;
grant execute on function public.set_my_location_visibility(boolean, boolean) to authenticated, service_role;

-- Per-friend overrides only suppress fresh precise coordinates.  They never
-- change the global distance policy and never preserve a coordinate snapshot.
create table private.precise_location_exclusions (
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  viewer_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_user_id, viewer_user_id),
  check (owner_user_id <> viewer_user_id)
);

revoke all on table private.precise_location_exclusions from public, anon, authenticated;

create function private.get_my_precise_location_exclusions_impl()
returns table (viewer_user_id uuid)
language sql stable security definer set search_path = ''
as $$
  select exclusion.viewer_user_id
  from private.precise_location_exclusions exclusion
  join public.friendships friendship
    on friendship.user_one_id = least(auth.uid(), exclusion.viewer_user_id)
   and friendship.user_two_id = greatest(auth.uid(), exclusion.viewer_user_id)
  where exclusion.owner_user_id = auth.uid();
$$;

create function private.set_precise_location_excluded_impl(
  friend_user_id uuid,
  is_excluded boolean
)
returns table (viewer_user_id uuid)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if friend_user_id is null or is_excluded is null or friend_user_id = auth.uid() then
    raise exception using errcode = '22023', message = 'invalid_precise_location_exclusion';
  end if;
  if not exists (
    select 1 from public.friendships friendship
    where friendship.user_one_id = least(auth.uid(), friend_user_id)
      and friendship.user_two_id = greatest(auth.uid(), friend_user_id)
  ) then
    raise exception using errcode = '42501', message = 'friendship_required';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  if is_excluded then
    insert into private.precise_location_exclusions (owner_user_id, viewer_user_id)
    values (auth.uid(), friend_user_id)
    on conflict on constraint precise_location_exclusions_pkey do nothing;
  else
    delete from private.precise_location_exclusions
    where owner_user_id = auth.uid()
      and private.precise_location_exclusions.viewer_user_id = friend_user_id;
  end if;
  return query select * from private.get_my_precise_location_exclusions_impl();
end;
$$;

create function public.get_my_precise_location_exclusions()
returns table (viewer_user_id uuid)
language sql security invoker set search_path = ''
as $$ select * from private.get_my_precise_location_exclusions_impl(); $$;

create function public.set_precise_location_excluded(
  friend_user_id uuid,
  is_excluded boolean
)
returns table (viewer_user_id uuid)
language sql security invoker set search_path = ''
as $$
  select * from private.set_precise_location_excluded_impl(friend_user_id, is_excluded);
$$;

revoke all on function private.get_my_precise_location_exclusions_impl() from public, anon;
revoke all on function private.set_precise_location_excluded_impl(uuid, boolean) from public, anon;
grant execute on function private.get_my_precise_location_exclusions_impl() to authenticated, service_role;
grant execute on function private.set_precise_location_excluded_impl(uuid, boolean) to authenticated, service_role;
grant execute on function public.get_my_precise_location_exclusions() to authenticated, service_role;
grant execute on function public.set_precise_location_excluded(uuid, boolean) to authenticated, service_role;

-- The exact-location result includes a non-sensitive state. It lets official
-- clients retain a previously cached point when the owner hides new updates,
-- without ever receiving a replacement coordinate.
create function private.get_friend_location_visibility_impl(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz,
  availability text
)
language plpgsql stable security definer set search_path = ''
as $$
declare is_friend boolean; may_share_precise boolean; is_excluded boolean;
begin
  if auth.uid() is null or friend_user_id is null then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
    return;
  end if;
  select exists(
    select 1 from public.friendships friendship
    where friendship.user_one_id = least(auth.uid(), friend_user_id)
      and friendship.user_two_id = greatest(auth.uid(), friend_user_id)
  ) into is_friend;
  if not is_friend then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
    return;
  end if;
  select coalesce(settings.share_precise_location, true)
  into may_share_precise
  from public.profiles profile
  left join private.search_privacy_settings settings on settings.user_id = profile.id
  where profile.id = friend_user_id;
  select exists(
    select 1 from private.precise_location_exclusions exclusion
    where exclusion.owner_user_id = friend_user_id and exclusion.viewer_user_id = auth.uid()
  ) into is_excluded;
  if not coalesce(may_share_precise, true) or is_excluded then
    return query select null::double precision, null::double precision, null::timestamptz, 'hidden'::text;
    return;
  end if;
  return query
  select location.latitude, location.longitude, location.updated_at, 'current'::text
  from public.user_locations location
  where location.user_id = friend_user_id
    and location.updated_at >= now() - interval '24 hours';
  if not found then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
  end if;
end;
$$;

create function public.get_friend_location_visibility(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz,
  availability text
)
language sql security invoker set search_path = ''
as $$ select * from private.get_friend_location_visibility_impl(friend_user_id); $$;

revoke all on function private.get_friend_location_visibility_impl(uuid) from public, anon;
grant execute on function private.get_friend_location_visibility_impl(uuid) to authenticated, service_role;
grant execute on function public.get_friend_location_visibility(uuid) to authenticated, service_role;

-- Keep the former three-column RPC for installed clients. It applies the same
-- policy but exposes a hidden location as the old empty result.
create or replace function private.get_friend_location_impl(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select result.latitude, result.longitude, result.updated_at
  from private.get_friend_location_visibility_impl(friend_user_id) result
  where result.availability = 'current';
$$;

-- A separate, private quota keeps a future profile page from making distance
-- computation a high-frequency location oracle. It is intentionally scoped to
-- one viewer/target pair so normal profile refreshes are unaffected.
create table private.location_distance_read_limits (
  viewer_user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1,
  primary key (viewer_user_id, target_user_id)
);

revoke all on table private.location_distance_read_limits from public, anon, authenticated;

create function private.consume_location_distance_read_quota(target_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  insert into private.location_distance_read_limits as limits (
    viewer_user_id, target_user_id, window_started_at, request_count
  ) values (auth.uid(), target_user_id, now(), 1)
  on conflict on constraint location_distance_read_limits_pkey do update set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  returning request_count into current_count;
  if current_count > 30 then
    raise exception using errcode = '42901', message = 'location_distance_rate_limited';
  end if;
end;
$$;

create function private.get_user_distance_impl(target_user_id uuid)
returns table (distance_value integer, distance_unit text, updated_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or target_user_id is null or target_user_id = auth.uid() then
    return;
  end if;
  perform private.consume_location_distance_read_quota(target_user_id);
  return query
  with locations as (
    select viewer.latitude as viewer_latitude, viewer.longitude as viewer_longitude,
           target.latitude as target_latitude, target.longitude as target_longitude,
           least(viewer.updated_at, target.updated_at) as updated_at
    from public.user_locations viewer
    join public.user_locations target on target.user_id = target_user_id
    left join private.search_privacy_settings settings on settings.user_id = target.user_id
    where viewer.user_id = auth.uid()
      and viewer.updated_at >= now() - interval '24 hours'
      and target.updated_at >= now() - interval '24 hours'
      and coalesce(settings.share_distance, true)
  ), metres as (
    select 6371000.0 * acos(least(1.0, greatest(-1.0,
      cos(radians(viewer_latitude)) * cos(radians(target_latitude)) *
      cos(radians(target_longitude) - radians(viewer_longitude)) +
      sin(radians(viewer_latitude)) * sin(radians(target_latitude))
    ))) as value, locations.updated_at
    from locations
  )
  select case when value < 1000 then round(value)::integer else round(value / 1000.0)::integer end,
         case when value < 1000 then 'meters' else 'kilometers' end,
         metres.updated_at
  from metres;
end;
$$;

create function public.get_user_distance(target_user_id uuid)
returns table (distance_value integer, distance_unit text, updated_at timestamptz)
language sql security invoker set search_path = ''
as $$ select * from private.get_user_distance_impl(target_user_id); $$;

revoke all on function private.consume_location_distance_read_quota(uuid) from public, anon;
revoke all on function private.get_user_distance_impl(uuid) from public, anon;
grant execute on function private.consume_location_distance_read_quota(uuid) to authenticated, service_role;
grant execute on function private.get_user_distance_impl(uuid) to authenticated, service_role;
grant execute on function public.get_user_distance(uuid) to authenticated, service_role;

-- A removed friendship must not leave an obsolete private override behind.
create or replace function private.broadcast_friend_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare first_user_id uuid; second_user_id uuid; conversation_id uuid;
begin
  if tg_table_name = 'friendships' and tg_op = 'DELETE' then
    first_user_id := old.user_one_id; second_user_id := old.user_two_id;
    delete from private.precise_location_exclusions exclusion
    where (exclusion.owner_user_id = first_user_id and exclusion.viewer_user_id = second_user_id)
       or (exclusion.owner_user_id = second_user_id and exclusion.viewer_user_id = first_user_id);
  elsif tg_table_name = 'friendships' then
    first_user_id := new.user_one_id; second_user_id := new.user_two_id;
  elsif tg_op = 'DELETE' then
    first_user_id := old.sender_id; second_user_id := old.recipient_id;
  else
    first_user_id := new.sender_id; second_user_id := new.recipient_id;
  end if;
  perform realtime.send(jsonb_build_object('table', tg_table_name, 'operation', tg_op), 'changed', 'user:' || first_user_id::text || ':friends', true);
  perform realtime.send(jsonb_build_object('table', tg_table_name, 'operation', tg_op), 'changed', 'user:' || second_user_id::text || ':friends', true);
  if tg_table_name = 'friendships' then
    select id into conversation_id from public.conversations
    where user_one_id = first_user_id and user_two_id = second_user_id;
    if conversation_id is not null then
      perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'), 'changed', 'user:' || first_user_id::text || ':chats', true);
      perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'), 'changed', 'user:' || second_user_id::text || ':chats', true);
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop function public.set_location_visibility(boolean);
drop function private.set_location_visibility_impl(boolean);
alter table public.profiles drop column share_location;
