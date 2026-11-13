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


select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000092', true);
set local role authenticated;
do $$ begin
  if not (select nearby_visible from public.get_my_search_privacy_settings()) then raise exception 'default false'; end if;
  perform public.set_my_search_privacy_setting('nearby', false);
  if (select nearby_visible from public.get_my_search_privacy_settings()) then raise exception 'not hidden'; end if;
  begin
    perform public.get_nearby_people();
    raise exception 'hidden viewer can read';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'nearby_visibility_disabled' then raise; end if;
  end;
  perform public.update_my_search_privacy_settings(false, true, false);
  perform public.set_my_last_seen_visibility('nobody');
  perform public.set_my_location_visibility(false, false);
  if (select nearby_visible from public.get_my_search_privacy_settings()) then raise exception 'legacy write reset visibility'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000091', true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.get_nearby_people('female') where id='10000000-0000-0000-0000-000000000092') then raise exception 'hidden target leaked'; end if;
end $$;
reset role;
update public.user_locations set updated_at=statement_timestamp()-interval '13 hours'
where user_id='10000000-0000-0000-0000-000000000092';
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000092', true);
set local role authenticated;
do $$ begin
  perform public.set_my_search_privacy_setting('nearby', true);
  begin
    perform public.get_nearby_people(); raise exception 'enabled with old geo';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'nearby_location_required' then raise; end if;
  end;
  if (select search_by_username from public.get_my_search_privacy_settings()) then raise exception 'enable reset search'; end if;
  if (select share_distance from public.get_my_search_privacy_settings()) then raise exception 'enable reset distance'; end if;
end $$;
reset role;
update public.user_locations set updated_at=statement_timestamp()
where user_id='10000000-0000-0000-0000-000000000092';
set local role authenticated;
do $$ begin
  perform public.get_nearby_people();
  begin
    perform public.set_my_search_privacy_setting('nearby', null); raise exception 'null accepted';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000091', true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from public.get_nearby_people('female') where id='10000000-0000-0000-0000-000000000092') then raise exception 'enabled target missing'; end if;
end $$;
reset role;
do $$ begin
  if has_function_privilege('anon', 'public.get_my_search_privacy_settings()', 'execute') or
     has_function_privilege('anon', 'public.set_my_search_privacy_setting(text,boolean)', 'execute') then raise exception 'anonymous ACL'; end if;
end $$;
rollback;
