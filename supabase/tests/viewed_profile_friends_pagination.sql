begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000811', false, false, '{"name":"Viewer"}'::jsonb),
  ('10000000-0000-0000-0000-000000000812', false, false, '{"name":"Target"}'::jsonb),
  ('10000000-0000-0000-0000-000000000813', false, false, '{"name":"Alice"}'::jsonb),
  ('10000000-0000-0000-0000-000000000814', false, false, '{"name":"Bob"}'::jsonb),
  ('10000000-0000-0000-0000-000000000815', false, false, '{"name":"Charlie"}'::jsonb),
  ('10000000-0000-0000-0000-000000000816', false, false, '{"name":"Mutual"}'::jsonb);

update public.profiles
set
  onboarding_completed = true,
  username = lower(display_name) || '_friends_test',
  last_seen_at = statement_timestamp()
where id between '10000000-0000-0000-0000-000000000811'::uuid
           and '10000000-0000-0000-0000-000000000816'::uuid;

insert into public.friendships (user_one_id, user_two_id)
values
  ('10000000-0000-0000-0000-000000000812', '10000000-0000-0000-0000-000000000813'),
  ('10000000-0000-0000-0000-000000000812', '10000000-0000-0000-0000-000000000814'),
  ('10000000-0000-0000-0000-000000000812', '10000000-0000-0000-0000-000000000815'),
  ('10000000-0000-0000-0000-000000000811', '10000000-0000-0000-0000-000000000813'),
  ('10000000-0000-0000-0000-000000000811', '10000000-0000-0000-0000-000000000816'),
  ('10000000-0000-0000-0000-000000000813', '10000000-0000-0000-0000-000000000816');

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000811',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000811","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  first_page text[];
  second_page text[];
  alice_mutual_count integer;
  first_page_has_more boolean;
  second_page_has_more boolean;
begin
  select
    array_agg(display_name order by display_name, id),
    max(mutual_friend_count) filter (where display_name = 'Alice'),
    bool_and(has_more)
  into first_page, alice_mutual_count, first_page_has_more
  from public.get_user_profile_friends(
    '10000000-0000-0000-0000-000000000812',
    null,
    null,
    2
  );

  if first_page is distinct from array['Alice', 'Bob']
     or alice_mutual_count <> 1
     or not first_page_has_more then
    raise exception 'First profile-friends page is incorrect: %, %, %',
      first_page, alice_mutual_count, first_page_has_more;
  end if;

  select
    array_agg(display_name order by display_name, id),
    bool_and(has_more)
  into second_page, second_page_has_more
  from public.get_user_profile_friends(
    '10000000-0000-0000-0000-000000000812',
    'Bob',
    '10000000-0000-0000-0000-000000000814',
    2
  );

  if second_page is distinct from array['Charlie']
     or second_page_has_more then
    raise exception 'Cursor page is incorrect: %, %', second_page, second_page_has_more;
  end if;

  -- Installed clients using the former single-argument call must receive the
  -- default first page through the new default parameters.
  if (select count(*) from public.get_user_profile_friends(
    '10000000-0000-0000-0000-000000000812'
  )) <> 3 then
    raise exception 'Default profile-friends RPC parameters are not compatible';
  end if;

  -- Three reads above consumed quota; nine more are accepted and the
  -- thirteenth request in one minute is rejected atomically.
  for attempt in 1..9 loop
    perform public.get_user_profile_friends(
      '10000000-0000-0000-0000-000000000812', null, null, 1
    );
  end loop;
  begin
    perform public.get_user_profile_friends(
      '10000000-0000-0000-0000-000000000812', null, null, 1
    );
    raise exception 'Profile-friends read quota was bypassed';
  exception when sqlstate '42901' then
    if sqlerrm <> 'profile_friends_rate_limited' then raise; end if;
  end;
end;
$$;

reset role;
rollback;
