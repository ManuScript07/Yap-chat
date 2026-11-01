begin;
-- Visibility is independent of location freshness and location sharing.
alter table private.search_privacy_settings add column if not exists nearby_visible boolean not null default true;

drop function public.get_my_search_privacy_settings();
drop function private.get_my_search_privacy_settings_impl();
drop function public.update_my_search_privacy_settings(boolean, boolean, boolean);
drop function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean);
drop function public.set_my_search_privacy_setting(text, boolean);
drop function private.set_my_search_privacy_setting_impl(text, boolean);
drop function public.set_my_last_seen_visibility(text);
drop function private.set_my_last_seen_visibility_impl(text);

drop function public.set_my_location_visibility(boolean, boolean);
drop function private.set_my_location_visibility_impl(boolean, boolean);

create function private.get_my_search_privacy_settings_impl()
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean,
  last_seen_visibility text,
  share_precise_location boolean,
  share_distance boolean, nearby_visible boolean
)
language sql stable security definer set search_path = ''
as $$
  select coalesce(settings.search_by_username, true),
         coalesce(settings.search_by_phone, true),
         coalesce(settings.search_by_name, true),
         coalesce(settings.last_seen_visibility, 'all'),
         coalesce(settings.share_precise_location, true),
         coalesce(settings.share_distance, true), coalesce(settings.nearby_visible, true)
  from (select auth.uid() as user_id) viewer
  left join private.search_privacy_settings settings on settings.user_id = viewer.user_id
  where viewer.user_id is not null;
$$;

create function private.set_my_search_privacy_setting_impl(
  setting_key text, is_enabled boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if setting_key not in ('username', 'phone', 'name', 'nearby') or is_enabled is null then
    raise exception using errcode = '22023', message = 'invalid_search_privacy_setting';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name,
    last_seen_visibility, share_precise_location, share_distance, nearby_visible, updated_at
  ) values (
    auth.uid(),
    case when setting_key = 'username' then is_enabled else true end,
    case when setting_key = 'phone' then is_enabled else true end,
    case when setting_key = 'name' then is_enabled else true end,
    'all', true, true, case when setting_key = 'nearby' then is_enabled else true end, now()
  ) on conflict (user_id) do update set
    search_by_username = case when setting_key = 'username' then is_enabled else settings.search_by_username end,
    search_by_phone = case when setting_key = 'phone' then is_enabled else settings.search_by_phone end,
    search_by_name = case when setting_key = 'name' then is_enabled else settings.search_by_name end,
    nearby_visible = case when setting_key = 'nearby' then is_enabled else settings.nearby_visible end,
    updated_at = now()
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility,
    settings.share_precise_location, settings.share_distance, settings.nearby_visible;
end;
$$;

create function private.update_my_search_privacy_settings_impl(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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
    settings.share_precise_location, settings.share_distance, settings.nearby_visible;
end;
$$;

create function private.set_my_last_seen_visibility_impl(visibility text)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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
    settings.share_precise_location, settings.share_distance, settings.nearby_visible;
  perform private.broadcast_last_seen_visibility_changed();
end;
$$;

create function private.set_my_location_visibility_impl(
  is_precise_location_shared boolean,
  is_distance_shared boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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
    settings.share_precise_location, settings.share_distance, settings.nearby_visible;
end;
$$;

create function public.get_my_search_privacy_settings()
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.get_my_search_privacy_settings_impl(); $$;

create function public.set_my_search_privacy_setting(setting_key text, is_enabled boolean)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_last_seen_visibility_impl(visibility); $$;

create function public.set_my_location_visibility(
  is_precise_location_shared boolean,
  is_distance_shared boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text, share_precise_location boolean, share_distance boolean, nearby_visible boolean
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


revoke all on function public.get_my_search_privacy_settings() from public, anon;

revoke all on function public.set_my_search_privacy_setting(text, boolean) from public, anon;

revoke all on function public.update_my_search_privacy_settings(boolean, boolean, boolean) from public, anon;

revoke all on function public.set_my_last_seen_visibility(text) from public, anon;

revoke all on function public.set_my_location_visibility(boolean, boolean) from public, anon;

create or replace function private.get_nearby_people_impl(
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

  if exists (select 1 from private.search_privacy_settings s
             where s.user_id = current_user_id and not s.nearby_visible) then
    raise exception using errcode = 'P0001', message = 'nearby_visibility_disabled';
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
      and not exists (select 1 from private.search_privacy_settings s
                      where s.user_id = profile.id and not s.nearby_visible)
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
    limit 150
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


notify pgrst, 'reload schema';
commit;
