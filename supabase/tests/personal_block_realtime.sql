begin;

-- The test uses a transaction and leaves the local database unchanged.
insert into auth.users (id, is_sso_user, is_anonymous)
values
  ('10000000-0000-0000-0000-0000000000a1', false, false),
  ('10000000-0000-0000-0000-0000000000a2', false, false),
  ('10000000-0000-0000-0000-0000000000a3', false, false),
  ('10000000-0000-0000-0000-0000000000a4', false, false);

update public.profiles
set
  display_name = case id
    when '10000000-0000-0000-0000-0000000000a1'::uuid then 'Non-friend blocker'
    when '10000000-0000-0000-0000-0000000000a2'::uuid then 'Non-friend target'
    when '10000000-0000-0000-0000-0000000000a3'::uuid then 'Friend blocker'
    else 'Friend target'
  end,
  onboarding_completed = true,
  birth_date = date '2000-01-01',
  terms_accepted_at = now(),
  privacy_accepted_at = now()
where id in (
  '10000000-0000-0000-0000-0000000000a1',
  '10000000-0000-0000-0000-0000000000a2',
  '10000000-0000-0000-0000-0000000000a3',
  '10000000-0000-0000-0000-0000000000a4'
);

-- Non-friends have no friendship/request trigger. A successful block must
-- still publish exactly one profile-cache invalidation per participant.
delete from realtime.messages;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a1', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;
select public.block_user('10000000-0000-0000-0000-0000000000a2');
reset role;

do $$
declare
  event_count integer;
begin
  select count(*) into event_count
  from realtime.messages
  where extension = 'broadcast'
    and event = 'changed'
    and topic in (
      'user:10000000-0000-0000-0000-0000000000a1:friends',
      'user:10000000-0000-0000-0000-0000000000a2:friends'
    )
    and payload @> '{"reason":"block","action":"blocked"}'::jsonb;
  if event_count <> 2 then
    raise exception 'expected two non-friend block events, got %', event_count;
  end if;
end;
$$;

-- The target's next profile request is server-redacted, not merely hidden by
-- the client. This is the response used by the realtime refresh.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a2', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;
do $$
declare
  profile_row record;
begin
  select * into profile_row
  from public.get_viewed_profile('10000000-0000-0000-0000-0000000000a1', false);
  if profile_row.relationship <> 'blocked'
     or profile_row.username <> ''
     or profile_row.avatar_url is not null
     or profile_row.birth_date is not null
     or profile_row.bio <> ''
     or profile_row.friend_count <> 0
     or profile_row.profile_view_count <> 0
     or profile_row.last_seen_at is not null then
    raise exception 'personally blocked viewed profile was not redacted';
  end if;
end;
$$;
reset role;

-- A former friend gets the same two block events, not the two generic delete
-- events plus two block events. The generic trigger still performs its
-- location-exclusion cleanup before it suppresses its broadcasts.
insert into public.friendships (user_one_id, user_two_id)
values (
  '10000000-0000-0000-0000-0000000000a3',
  '10000000-0000-0000-0000-0000000000a4'
);
delete from realtime.messages;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a3', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
set local role authenticated;
select public.block_user('10000000-0000-0000-0000-0000000000a4');
reset role;

do $$
declare
  event_count integer;
begin
  if exists (
    select 1 from public.friendships
    where user_one_id = '10000000-0000-0000-0000-0000000000a3'
      and user_two_id = '10000000-0000-0000-0000-0000000000a4'
  ) then
    raise exception 'friendship survived personal block';
  end if;

  select count(*) into event_count
  from realtime.messages
  where extension = 'broadcast'
    and event = 'changed'
    and topic in (
      'user:10000000-0000-0000-0000-0000000000a3:friends',
      'user:10000000-0000-0000-0000-0000000000a4:friends'
    )
    and payload @> '{"reason":"block","action":"blocked"}'::jsonb;
  if event_count <> 2 then
    raise exception 'expected exactly two former-friend block events, got %', event_count;
  end if;

  select count(*) into event_count
  from realtime.messages
  where extension = 'broadcast'
    and event = 'changed'
    and topic in (
      'user:10000000-0000-0000-0000-0000000000a3:friends',
      'user:10000000-0000-0000-0000-0000000000a4:friends'
    );
  if event_count <> 2 then
    raise exception 'duplicate former-friend invalidation events: %', event_count;
  end if;
end;
$$;

rollback;
