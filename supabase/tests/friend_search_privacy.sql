-- Run on local Supabase with psql -v ON_ERROR_STOP=1. All fixtures roll back.
-- Exercise the public RPC as authenticated, not as the database owner.
begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
select
  ('70000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  false, false, jsonb_build_object('name', 'Privacy fixture ' || n)
from generate_series(1, 34) n;

update public.profiles
set onboarding_completed = id <> '70000000-0000-0000-0000-000000000007',
    username = case right(id::text, 3)
      when '001' then 'privacy_viewer'
      when '002' then 'privacy_target'
      when '003' then 'privacy_friend'
      when '004' then 'privacy_incoming'
      when '005' then 'privacy_outgoing'
      when '006' then 'privacy_default'
      when '007' then 'privacy_incomplete'
      else 'privacy_limit_' || right(id::text, 3)
    end,
    display_name = case right(id::text, 3)
      when '001' then 'Privacyviewer'
      when '002' then 'Privacyscope Target'
      when '003' then 'Privacyscope Friend'
      when '004' then 'Privacyscope Incoming'
      when '005' then 'Privacyscope Outgoing'
      when '006' then 'Privacydefault'
      when '007' then 'Privacyincomplete'
      else 'Privacycap Candidate ' || right(id::text, 3)
    end,
    show_friends_count = id <> '70000000-0000-0000-0000-000000000003',
    birth_date = date '2000-01-01'
where id between '70000000-0000-0000-0000-000000000001'::uuid
             and '70000000-0000-0000-0000-000000000034'::uuid;

-- Twelve hidden name matches sort before the second visible match. Filtering
-- only after LIMIT would lose that match; exact-name ranking must stay intact.
update public.profiles
set display_name = case right(id::text, 3)
      when '033' then 'Privacyfiltered'
      when '034' then 'Privacyfiltered Visible'
      else 'Privacyfiltered A Hidden ' || right(id::text, 3)
    end
where id between '70000000-0000-0000-0000-000000000021'::uuid
             and '70000000-0000-0000-0000-000000000034'::uuid;
insert into private.search_privacy_settings (user_id, search_by_name)
select id, false from public.profiles
where id between '70000000-0000-0000-0000-000000000021'::uuid
             and '70000000-0000-0000-0000-000000000032'::uuid;

update public.profiles
set phone_lookup_hash = private.phone_lookup_hash('+79990000802')
where id = '70000000-0000-0000-0000-000000000002';

insert into private.search_privacy_settings
  (user_id, search_by_username, search_by_name, search_by_phone)
select id, false, false, false
from public.profiles
where id between '70000000-0000-0000-0000-000000000003'::uuid
             and '70000000-0000-0000-0000-000000000005'::uuid;

insert into public.friendships (user_one_id, user_two_id, created_at)
values
  ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000003', now() - interval '3 days'),
  ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000008', now() - interval '1 hour'),
  ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000009', now());

insert into public.friend_requests (sender_id, recipient_id)
values
  ('70000000-0000-0000-0000-000000000004', '70000000-0000-0000-0000-000000000001'),
  ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000005');

create function pg_temp.assert_search(
  query_text text, expected_ids uuid[], expected_relationship text default null
)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  actual_ids uuid[];
  actual_relationships text[];
begin
  if current_user <> 'authenticated' then
    raise exception 'Test must exercise the authenticated RPC role';
  end if;
  select coalesce(array_agg(candidate.id order by candidate.id), '{}'::uuid[]),
         array_agg(candidate.relationship order by candidate.id)
  into actual_ids, actual_relationships
  from public.search_friend_candidates(query_text, 10) candidate;
  if actual_ids is distinct from expected_ids then
    raise exception 'Search %: expected %, got %', query_text, expected_ids, actual_ids;
  end if;
  if expected_relationship is not null
     and actual_relationships is distinct from array[expected_relationship] then
    raise exception 'Search %: wrong relationship %', query_text, actual_relationships;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"70000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

-- No settings row means enabled. Exact, normalized username and name-prefix
-- search retain their old matching rules.
select pg_temp.assert_search('  @PRIVACY_TARGET  ', array['70000000-0000-0000-0000-000000000002'::uuid], 'none');
select pg_temp.assert_search('Privacydefault', array['70000000-0000-0000-0000-000000000006'::uuid], 'none');
select pg_temp.assert_search('@privacy_def', '{}'::uuid[]);
select pg_temp.assert_search('@privacy_viewer', '{}'::uuid[]);
select pg_temp.assert_search('Privacyviewer', '{}'::uuid[]);
select pg_temp.assert_search('@privacy_incomplete', '{}'::uuid[]);
select pg_temp.assert_search('Privacyincomplete', '{}'::uuid[]);
select pg_temp.assert_search('@privacy-target', '{}'::uuid[]);
select pg_temp.assert_search('@', '{}'::uuid[]);
select pg_temp.assert_search('pr', '{}'::uuid[]);
select pg_temp.assert_search(null, '{}'::uuid[]);

-- Disable discovery through the same setting RPC used by the application.
reset role;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"70000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select * from public.set_my_search_privacy_setting('username', false);
select * from public.set_my_search_privacy_setting('name', false);
select * from public.set_my_search_privacy_setting('phone', false);
reset role;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"70000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select pg_temp.assert_search('@privacy_target', '{}'::uuid[]);
select pg_temp.assert_search('  @PRIVACY_TARGET  ', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Target', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope', array['70000000-0000-0000-0000-000000000003'::uuid], 'friend');
select pg_temp.assert_search('@privacy_incoming', '{}'::uuid[]);
select pg_temp.assert_search('@privacy_outgoing', '{}'::uuid[]);

do $$
begin
  if exists (select 1 from public.get_friends_page(null, null, 2)
             where id = '70000000-0000-0000-0000-000000000003') then
    raise exception 'Friend fixture must be outside the loaded first page';
  end if;
  if exists (select 1 from public.match_contact_phones(array['+79990000802'])) then
    raise exception 'Phone privacy no longer hides a non-friend';
  end if;
  if public.resolve_shared_profile_username('privacy_target') is distinct from
     '70000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'Explicit profile link was incorrectly restricted by search privacy';
  end if;
  if exists (select 1 from public.search_friend_candidates('@privacy_friend', 10)
             where friend_count is not null) then
    raise exception 'Search disclosed a hidden friend count';
  end if;
  if (select count(*) from public.search_friend_candidates('Privacycap', 1000)) <> 10
     or (select count(*) from public.search_friend_candidates('Privacycap', 2)) <> 2
     or (select count(*) from public.search_friend_candidates('Privacycap', 0)) <> 1 then
    raise exception 'Search result caps changed';
  end if;
  if (select array_agg(id) from public.search_friend_candidates('Privacyfiltered', 10))
     is distinct from array['70000000-0000-0000-0000-000000000033'::uuid,
                            '70000000-0000-0000-0000-000000000034'::uuid]
     or (select id from public.search_friend_candidates('Privacyfiltered', 1))
        is distinct from '70000000-0000-0000-0000-000000000033'::uuid then
    raise exception 'Privacy filtering consumed result slots or changed exact-name ranking';
  end if;
end;
$$;
select pg_temp.assert_search('@privacy_friend', array['70000000-0000-0000-0000-000000000003'::uuid], 'friend');

-- An enabled name flag must not bypass a disabled username flag, or vice versa.
reset role;
update private.search_privacy_settings set search_by_name = true
where user_id = '70000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_search('@privacy_target', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Target', array['70000000-0000-0000-0000-000000000002'::uuid], 'none');
reset role;
update private.search_privacy_settings set search_by_name = false, search_by_username = true
where user_id = '70000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_search('@privacy_target', array['70000000-0000-0000-0000-000000000002'::uuid], 'none');
select pg_temp.assert_search('Privacyscope Target', '{}'::uuid[]);

-- Both request directions retain their relationship only while discoverable.
reset role;
update private.search_privacy_settings set search_by_name = true, search_by_username = true
where user_id in ('70000000-0000-0000-0000-000000000004', '70000000-0000-0000-0000-000000000005');
set local role authenticated;
select pg_temp.assert_search('@privacy_incoming', array['70000000-0000-0000-0000-000000000004'::uuid], 'incoming');
select pg_temp.assert_search('@privacy_outgoing', array['70000000-0000-0000-0000-000000000005'::uuid], 'outgoing');

-- Establishing/removing friendship must enable/remove the exception immediately.
reset role;
update private.search_privacy_settings set search_by_name = false, search_by_username = false
where user_id = '70000000-0000-0000-0000-000000000002';
insert into public.friendships (user_one_id, user_two_id)
values ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.assert_search('@privacy_target', array['70000000-0000-0000-0000-000000000002'::uuid], 'friend');
select pg_temp.assert_search('Privacyscope Target', array['70000000-0000-0000-0000-000000000002'::uuid], 'friend');
do $$
begin
  if not exists (select 1 from public.match_contact_phones(array['+79990000802'])
                 where relationship = 'friend') then
    raise exception 'Phone discovery lost the existing-friend exception';
  end if;
end;
$$;
reset role;
delete from public.friendships
where user_one_id = '70000000-0000-0000-0000-000000000001'
  and user_two_id = '70000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_search('@privacy_target', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Target', '{}'::uuid[]);

-- The friend exception must not bypass personal blocks, global bans or deletion.
reset role;
insert into public.user_blocks (blocker_user_id, blocked_user_id)
values ('70000000-0000-0000-0000-000000000003', '70000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.assert_search('@privacy_friend', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Friend', '{}'::uuid[]);
reset role;
delete from public.user_blocks
where blocker_user_id = '70000000-0000-0000-0000-000000000003'
  and blocked_user_id = '70000000-0000-0000-0000-000000000001';
insert into private.global_account_bans (target_user_id, note)
values ('70000000-0000-0000-0000-000000000003', 'Local search privacy regression test');
set local role authenticated;
select pg_temp.assert_search('@privacy_friend', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Friend', '{}'::uuid[]);
reset role;
update private.global_account_bans set revoked_at = now()
where target_user_id = '70000000-0000-0000-0000-000000000003';
insert into private.account_deletion_requests (target_user_id, requested_by, note)
values ('70000000-0000-0000-0000-000000000003', 'admin', 'Local search privacy regression test');
set local role authenticated;
select pg_temp.assert_search('@privacy_friend', '{}'::uuid[]);
select pg_temp.assert_search('Privacyscope Friend', '{}'::uuid[]);

reset role;
do $$
begin
  if has_function_privilege('anon', 'public.search_friend_candidates(text,integer)', 'EXECUTE')
     or has_function_privilege('anon', 'private.search_friend_candidates_impl(text,integer)', 'EXECUTE') then
    raise exception 'Anonymous discovery access was introduced';
  end if;
  if has_table_privilege('authenticated', 'public.public_profiles', 'SELECT')
     or has_table_privilege('anon', 'public.public_profiles', 'SELECT')
     or has_function_privilege('authenticated', 'private.get_public_profiles_impl()', 'EXECUTE')
     or has_function_privilege('anon', 'private.get_public_profiles_impl()', 'EXECUTE') then
    raise exception 'Legacy profile discovery bypass remains accessible';
  end if;
  if not has_table_privilege('service_role', 'public.public_profiles', 'SELECT')
     or not has_function_privilege('service_role', 'private.get_public_profiles_impl()', 'EXECUTE') then
    raise exception 'Administrative legacy profile access was lost';
  end if;
end;
$$;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
set local role authenticated;
select pg_temp.assert_search('@privacy_default', '{}'::uuid[]);
select pg_temp.assert_search('Privacydefault', '{}'::uuid[]);
reset role;

rollback;
