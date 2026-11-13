begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000091', false, false, '{"name":"Viewer"}'::jsonb),
  ('10000000-0000-0000-0000-000000000092', false, false, '{"name":"Near"}'::jsonb),
  ('10000000-0000-0000-0000-000000000093', false, false, '{"name":"Far"}'::jsonb),
  ('10000000-0000-0000-0000-000000000094', false, false, '{"name":"Inactive"}'::jsonb),
  ('10000000-0000-0000-0000-000000000095', false, false, '{"name":"Personally blocked"}'::jsonb),
  ('10000000-0000-0000-0000-000000000096', false, false, '{"name":"Globally banned"}'::jsonb);

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
select
  ('10000000-0000-0000-0000-' || lpad(candidate::text, 12, '0'))::uuid,
  false,
  false,
  jsonb_build_object('name', 'Candidate ' || candidate)
from generate_series(101, 260) as candidate;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values ('10000000-0000-0000-0000-000000000097', false, false, '{"name":"Bounded viewer"}'::jsonb);

update public.profiles
set onboarding_completed = true,
    birth_date = date '1998-01-01',
    gender = 'female',
    last_seen_at = statement_timestamp()
where id between '10000000-0000-0000-0000-000000000091'::uuid
           and '10000000-0000-0000-0000-000000000096'::uuid;

update public.profiles
set last_seen_at = statement_timestamp() - interval '4 days'
where id = '10000000-0000-0000-0000-000000000094';

update public.profiles
set onboarding_completed = true,
    birth_date = date '1998-01-01',
    gender = 'male',
    last_seen_at = statement_timestamp()
where id between '10000000-0000-0000-0000-000000000101'::uuid
           and '10000000-0000-0000-0000-000000000260'::uuid;

insert into public.user_locations (user_id, latitude, longitude, updated_at)
values
  ('10000000-0000-0000-0000-000000000091', -40.7500, -100.6100, statement_timestamp()),
  ('10000000-0000-0000-0000-000000000092', -40.7510, -100.6110, statement_timestamp()),
  ('10000000-0000-0000-0000-000000000093', 59.9343, 30.3351, statement_timestamp()),
  ('10000000-0000-0000-0000-000000000094', -40.7520, -100.6120, statement_timestamp()),
  ('10000000-0000-0000-0000-000000000095', -40.7530, -100.6130, statement_timestamp()),
  ('10000000-0000-0000-0000-000000000096', -40.7540, -100.6140, statement_timestamp());

insert into public.user_locations (user_id, latitude, longitude, updated_at)
select
  ('10000000-0000-0000-0000-' || lpad(candidate::text, 12, '0'))::uuid,
  -40.75 + candidate::double precision / 100000.0,
  -100.61,
  statement_timestamp()
from generate_series(101, 260) as candidate;

insert into public.user_locations (user_id, latitude, longitude, updated_at)
values ('10000000-0000-0000-0000-000000000097', -40.75, -100.61, statement_timestamp());

insert into public.user_blocks (blocker_user_id, blocked_user_id)
values ('10000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000095');

insert into private.global_account_bans (target_user_id, note)
values ('10000000-0000-0000-0000-000000000096', 'nearby test');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000091', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  result_ids uuid[];
begin
  select array_agg(id order by id)
  into result_ids
  from public.get_nearby_people('female', 18, 99, null, 30);

  if result_ids is distinct from array['10000000-0000-0000-0000-000000000092'::uuid] then
    raise exception 'Nearby feed leaked an inactive, blocked, banned, or distant account: %', result_ids;
  end if;

  if exists (
    select 1
    from information_schema.parameters
    where specific_schema = 'public'
      and specific_name like 'get_nearby_people%'
      and parameter_name in ('latitude', 'longitude', 'distance_meters')
  ) then
    raise exception 'Nearby RPC exposes a location or distance parameter';
  end if;

  begin
    perform public.get_nearby_people('female', 17, 99, null, 1);
    raise exception 'Nearby feed accepted an underage filter';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_nearby_age_range' then raise; end if;
  end;

  -- The first lookup above consumed one request; seven more are accepted and
  -- the ninth request in the same server minute must be rejected atomically.
  for counter in 1..7 loop
    perform public.get_nearby_people('female', 18, 99, null, 1);
  end loop;
  begin
    perform public.get_nearby_people('female', 18, 99, null, 1);
    raise exception 'Nearby read quota was bypassed';
  exception when sqlstate '42901' then
    if sqlerrm <> 'nearby_rate_limited' then raise; end if;
  end;
end;
$$;

reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000097', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000097","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  first_page uuid[];
  second_page uuid[];
  third_page uuid[];
  fourth_page uuid[];
  fifth_page uuid[];
  sixth_page uuid[];
begin
  select array_agg(id) into first_page
  from public.get_nearby_people('male', 18, 99, null, 30);
  select array_agg(id) into second_page
  from public.get_nearby_people('male', 18, 99, first_page[30], 30);
  select array_agg(id) into third_page
  from public.get_nearby_people('male', 18, 99, second_page[30], 30);
  select array_agg(id) into fourth_page
  from public.get_nearby_people('male', 18, 99, third_page[30], 30);
  select array_agg(id) into fifth_page
  from public.get_nearby_people('male', 18, 99, fourth_page[30], 30);

  select array_agg(id) into sixth_page
  from public.get_nearby_people('male', 18, 99, fifth_page[30], 30);

  if cardinality(first_page) <> 30
     or cardinality(second_page) <> 30
     or cardinality(third_page) <> 30
     or cardinality(fourth_page) <> 30
     or cardinality(fifth_page) <> 30
     or coalesce(cardinality(sixth_page), 0) <> 0 then
    raise exception 'Nearby feed did not stop after its first 150 people';
  end if;

  if cardinality(
    array(select unnest(first_page) union select unnest(second_page)
          union select unnest(third_page) union select unnest(fourth_page) union select unnest(fifth_page))
  ) <> 150 then
    raise exception 'Nearby cursor pagination returned duplicate people';
  end if;
end;
$$;

reset role;
rollback;
