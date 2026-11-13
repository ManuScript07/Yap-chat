begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000901', false, false, '{"name":"Presence A"}'::jsonb),
  ('10000000-0000-0000-0000-000000000902', false, false, '{"name":"Presence B"}'::jsonb);

update public.profiles
set onboarding_completed = true,
    birth_date = date '1995-01-01',
    last_seen_at = now()
where id in (
  '10000000-0000-0000-0000-000000000901',
  '10000000-0000-0000-0000-000000000902'
);

insert into public.friendships (user_one_id, user_two_id)
values (
  '10000000-0000-0000-0000-000000000901',
  '10000000-0000-0000-0000-000000000902'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000901',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000901","role":"authenticated"}',
  true
);
set local role authenticated;
select public.touch_my_presence_session(
  '20000000-0000-0000-0000-000000000901'
);
select public.create_direct_conversation(
  '10000000-0000-0000-0000-000000000902'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000902',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000902","role":"authenticated"}',
  true
);
set local role authenticated;
select public.touch_my_presence_session(
  '20000000-0000-0000-0000-000000000902'
);
select public.touch_my_presence_session(
  '20000000-0000-0000-0000-000000000903'
);
reset role;

do $$
begin
  if not private.is_user_online('10000000-0000-0000-0000-000000000901')
     or not private.is_user_online('10000000-0000-0000-0000-000000000902') then
    raise exception 'presence sessions were not marked online';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000901',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000901","role":"authenticated"}',
  true
);
set local role authenticated;
do $$
declare
  status boolean;
begin
  select profile.is_online into status
  from public.get_viewed_profile(
    '10000000-0000-0000-0000-000000000902',
    false
  ) profile;
  if status is distinct from true then
    raise exception 'viewed profile did not include online state';
  end if;

  select friend.is_online into status
  from public.get_friends_page(null, null, 50) friend
  where friend.id = '10000000-0000-0000-0000-000000000902';
  if status is distinct from true then
    raise exception 'friends response did not include online state';
  end if;

  select chat.peer_is_online into status
  from public.get_chat_summaries() chat
  where chat.peer_id = '10000000-0000-0000-0000-000000000902';
  if status is distinct from true then
    raise exception 'chat summaries did not include online state';
  end if;

  select result.is_online into status
  from public.set_my_presence_watch_scope(
    '20000000-0000-0000-0000-000000000901',
    'nearby:test',
    array['10000000-0000-0000-0000-000000000902'::uuid]
  ) result;
  if status is distinct from true then
    raise exception 'watch scope did not return the target online snapshot';
  end if;
end;
$$;
reset role;

do $$
begin
  if not exists (
    select 1 from private.user_presence_watch_targets watch
    where watch.watcher_user_id = '10000000-0000-0000-0000-000000000901'
      and watch.target_user_id = '10000000-0000-0000-0000-000000000902'
  ) then
    raise exception 'watch target was not registered';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000902',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000902","role":"authenticated"}',
  true
);
set local role authenticated;
select public.close_my_presence_session(
  '20000000-0000-0000-0000-000000000902'
);
reset role;

do $$
begin
  if not private.is_user_online('10000000-0000-0000-0000-000000000902') then
    raise exception 'closing one of two sessions incorrectly marked user offline';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000902',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000902","role":"authenticated"}',
  true
);
set local role authenticated;
select public.close_my_presence_session(
  '20000000-0000-0000-0000-000000000903'
);
reset role;

do $$
begin
  if private.is_user_online('10000000-0000-0000-0000-000000000902') then
    raise exception 'closing the final session did not mark user offline';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname in (
        'Authenticated users can receive presence',
        'Authenticated users can track presence'
      )
  ) then
    raise exception 'legacy global presence policies still exist';
  end if;
end;
$$;

-- Blocking A -> B must immediately revoke B's ability to watch A, while the
-- directed rule still permits A to watch B.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000902',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000902","role":"authenticated"}',
  true
);
set local role authenticated;
select public.touch_my_presence_session(
  '20000000-0000-0000-0000-000000000904'
);
select * from public.set_my_presence_watch_scope(
  '20000000-0000-0000-0000-000000000904',
  'profile:test',
  array['10000000-0000-0000-0000-000000000901'::uuid]
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000901',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000901","role":"authenticated"}',
  true
);
set local role authenticated;
select public.block_user('10000000-0000-0000-0000-000000000902');
reset role;

do $$
begin
  if exists (
    select 1 from private.user_presence_watch_targets watch
    where watch.watcher_user_id = '10000000-0000-0000-0000-000000000902'
      and watch.target_user_id = '10000000-0000-0000-0000-000000000901'
  ) then
    raise exception 'personal block did not revoke the directed watch';
  end if;
end;
$$;

-- An administrator-created global ban must terminate every active app
-- session for that account without affecting another user's session.
insert into private.global_account_bans (target_user_id, created_by, note)
values (
  '10000000-0000-0000-0000-000000000902',
  'presence-test',
  'presence-test'
);

do $$
begin
  if private.is_user_online('10000000-0000-0000-0000-000000000902')
     or exists (
       select 1 from private.user_presence_sessions session
       where session.user_id = '10000000-0000-0000-0000-000000000902'
     ) then
    raise exception 'global ban did not terminate the target presence';
  end if;
  if not private.is_user_online('10000000-0000-0000-0000-000000000901') then
    raise exception 'global ban incorrectly affected another user presence';
  end if;
end;
$$;

rollback;
