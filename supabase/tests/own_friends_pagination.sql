begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000917', false, false, '{"name":"Friend 917"}'::jsonb),
  ('10000000-0000-0000-0000-000000000918', false, false, '{"name":"Friend 918"}'::jsonb),
  ('10000000-0000-0000-0000-000000000919', false, false, '{"name":"Friend 919"}'::jsonb),
  ('10000000-0000-0000-0000-000000000920', false, false, '{"name":"Owner 920"}'::jsonb),
  ('10000000-0000-0000-0000-000000000921', false, false, '{"name":"Friend 921"}'::jsonb),
  ('10000000-0000-0000-0000-000000000922', false, false, '{"name":"Friend 922"}'::jsonb);

update public.profiles
set onboarding_completed = true,
    username = 'friends_page_' || right(id::text, 3),
    last_seen_at = statement_timestamp()
where id between '10000000-0000-0000-0000-000000000917'::uuid
           and '10000000-0000-0000-0000-000000000922'::uuid;

update public.profiles
set phone_lookup_hash = private.phone_lookup_hash('+79990000922')
where id = '10000000-0000-0000-0000-000000000922';

insert into public.friendships (user_one_id, user_two_id, created_at)
values
  ('10000000-0000-0000-0000-000000000917', '10000000-0000-0000-0000-000000000920', '2026-09-06 10:05:00+00'),
  ('10000000-0000-0000-0000-000000000918', '10000000-0000-0000-0000-000000000920', '2026-09-06 10:04:00+00'),
  ('10000000-0000-0000-0000-000000000919', '10000000-0000-0000-0000-000000000920', '2026-09-06 10:03:00+00'),
  ('10000000-0000-0000-0000-000000000920', '10000000-0000-0000-0000-000000000921', '2026-09-06 10:02:00+00'),
  ('10000000-0000-0000-0000-000000000920', '10000000-0000-0000-0000-000000000922', '2026-09-06 10:01:00+00');

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000920',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000920","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  first_ids uuid[];
  second_ids uuid[];
  final_ids uuid[];
  first_cursor_since timestamptz;
  first_cursor_id uuid;
  has_more boolean;
  total integer;
  current_friend_id uuid;
  search_relationship text;
  phone_relationship text;
begin
  if to_regprocedure('public.get_friends()') is not null then
    raise exception 'The unbounded get_friends RPC must not be exposed';
  end if;

  select
    array_agg(friend.id order by friend.friends_since desc, friend.id desc),
    bool_and(friend.has_more),
    max(friend.total_count)
  into first_ids, has_more, total
  from public.get_friends_page(null, null, 2) friend;

  -- The cursor is taken from the second returned row, not from an aggregate.
  select friend.friends_since, friend.id
  into first_cursor_since, first_cursor_id
  from public.get_friends_page(null, null, 2) friend
  order by friend.friends_since asc, friend.id asc
  limit 1;

  if first_ids is distinct from array[
    '10000000-0000-0000-0000-000000000917'::uuid,
    '10000000-0000-0000-0000-000000000918'::uuid
  ] or not has_more or total <> 5 then
    raise exception 'First own-friends page is incorrect: %, %, %',
      first_ids, has_more, total;
  end if;

  select
    array_agg(friend.id order by friend.friends_since desc, friend.id desc),
    bool_and(friend.has_more)
  into second_ids, has_more
  from public.get_friends_page(first_cursor_since, first_cursor_id, 2) friend;

  if second_ids is distinct from array[
    '10000000-0000-0000-0000-000000000919'::uuid,
    '10000000-0000-0000-0000-000000000921'::uuid
  ] or not has_more then
    raise exception 'Second own-friends page is incorrect: %, %', second_ids, has_more;
  end if;

  select friend.friends_since, friend.id
  into first_cursor_since, first_cursor_id
  from public.get_friends_page(first_cursor_since, first_cursor_id, 2) friend
  order by friend.friends_since asc, friend.id asc
  limit 1;

  select
    array_agg(friend.id order by friend.friends_since desc, friend.id desc),
    bool_and(friend.has_more)
  into final_ids, has_more
  from public.get_friends_page(first_cursor_since, first_cursor_id, 2) friend;

  if final_ids is distinct from array[
    '10000000-0000-0000-0000-000000000922'::uuid
  ] or has_more then
    raise exception 'Final own-friends page is incorrect: %, %', final_ids, has_more;
  end if;

  select friend.id into current_friend_id
  from public.get_current_friend('10000000-0000-0000-0000-000000000921') friend;
  if current_friend_id <> '10000000-0000-0000-0000-000000000921'::uuid then
    raise exception 'Single cached friend refresh returned the wrong row';
  end if;

  -- Friend 922 is outside the first two-row page. Every discovery path must
  -- still recognise the existing friendship and provide a safe cache row.
  select candidate.relationship into search_relationship
  from public.search_friend_candidates('@friends_page_922', 10) candidate;
  if search_relationship <> 'friend' then
    raise exception 'Username search did not recognise a friend outside the page';
  end if;

  select candidate.relationship into phone_relationship
  from public.match_contact_phones(array['+79990000922']) candidate;
  if phone_relationship <> 'friend' then
    raise exception 'Phone search did not recognise a friend outside the page';
  end if;

  select friend.id into current_friend_id
  from public.get_current_friends(array[
    '10000000-0000-0000-0000-000000000922'::uuid
  ]) friend;
  if current_friend_id <> '10000000-0000-0000-0000-000000000922'::uuid then
    raise exception 'Batch cache lookup did not return the searched friend';
  end if;

  begin
    perform public.get_friends_page(now(), null, 2);
    raise exception 'Invalid own-friends cursor was accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_friends_cursor' then raise; end if;
  end;
end;
$$;

reset role;
rollback;
