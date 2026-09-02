-- The public RPC must remain SECURITY INVOKER so it is safe to expose through
-- PostgREST. Its implementation needs controlled access to locations, which
-- are deliberately not selectable by signed-in users under RLS.
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
  has_more boolean
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
  if normalized_minimum_age < 14
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
  ), limited as materialized (
    select candidate.*
    from candidates candidate
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
    exists (select 1 from limited offset normalized_page_size) as has_more
  from page
  order by page.distance_meters, page.id;
end;
$$;

create or replace function public.get_nearby_people(
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
  has_more boolean
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

revoke all on function private.get_nearby_people_impl(text, integer, integer, uuid, integer)
  from public, anon;
grant execute on function private.get_nearby_people_impl(text, integer, integer, uuid, integer)
  to authenticated, service_role;
