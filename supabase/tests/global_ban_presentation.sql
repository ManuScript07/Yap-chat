begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000081', false, false, '{"name":"Viewer"}'::jsonb),
  ('10000000-0000-0000-0000-000000000082', false, false, '{"name":"Globally banned"}'::jsonb),
  ('10000000-0000-0000-0000-000000000083', false, false, '{"name":"Unaffected"}'::jsonb);

update public.profiles
set onboarding_completed = true
where id in (
  '10000000-0000-0000-0000-000000000081',
  '10000000-0000-0000-0000-000000000082',
  '10000000-0000-0000-0000-000000000083'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000081","role":"authenticated"}', true);
set local role authenticated;
select public.create_direct_conversation('10000000-0000-0000-0000-000000000082');
reset role;

insert into private.global_account_bans (target_user_id, note)
values ('10000000-0000-0000-0000-000000000082', 'presentation test');

do $$
begin
  if not private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000082'
  ) then
    raise exception 'The linked account was not globally banned';
  end if;
  if private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000081'
  ) or private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000083'
  ) then
    raise exception 'An unrelated account was globally banned';
  end if;
end;
$$;

set local role authenticated;
do $$
declare
  viewed_name text;
  viewed_username text;
  chat_name text;
  chat_avatar text;
  chat_globally_banned boolean;
  chat_id uuid;
  search_count integer;
begin
  select display_name, username into viewed_name, viewed_username
  from public.get_viewed_profile('10000000-0000-0000-0000-000000000082', false);
  if viewed_name <> 'Заблокированный пользователь' or viewed_username <> '' then
    raise exception 'Globally banned profile was not redacted';
  end if;

  select id, peer_display_name, peer_avatar_url, peer_is_globally_banned
  into chat_id, chat_name, chat_avatar, chat_globally_banned
  from public.get_chat_summaries()
  where peer_id = '10000000-0000-0000-0000-000000000082';
  if chat_name <> 'Заблокированный пользователь'
     or chat_avatar is not null or chat_globally_banned is not true then
    raise exception 'Globally banned chat summary was not redacted';
  end if;

  select count(*) into search_count
  from public.search_friend_candidates('@globally_banned', 10)
  where id = '10000000-0000-0000-0000-000000000082';
  if search_count <> 0 then
    raise exception 'Globally banned account was returned from search';
  end if;

  begin
    perform public.send_friend_request('10000000-0000-0000-0000-000000000082');
    raise exception 'Friend request to globally banned account was allowed';
  exception when sqlstate '42501' then
    if sqlerrm <> 'friend_request_blocked' then raise; end if;
  end;

  begin
    perform public.send_chat_message(
      extensions.gen_random_uuid(), chat_id, 'text', 'must not be delivered'
    );
    raise exception 'Message to globally banned account was allowed';
  exception when sqlstate '42501' then
    if sqlerrm <> 'conversation_blocked' then raise; end if;
  end;
end;
$$;

reset role;
update private.global_account_bans
set revoked_at = now()
where target_user_id = '10000000-0000-0000-0000-000000000082';

do $$
begin
  if private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000082'
  ) then
    raise exception 'Revoked global ban still restricted its target';
  end if;
  if private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000081'
  ) or private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000083'
  ) then
    raise exception 'Revoking a ban changed an unrelated account status';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000081', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000081","role":"authenticated"}', true);
set local role authenticated;
do $$
declare
  restored_chat_id uuid;
  request_id uuid;
begin
  select id into restored_chat_id
  from public.get_chat_summaries()
  where peer_id = '10000000-0000-0000-0000-000000000082';
  if private.is_user_pair_blocked_impl(
    '10000000-0000-0000-0000-000000000081',
    '10000000-0000-0000-0000-000000000082'
  ) then
    raise exception 'Unexpected personal block remained after global unban';
  end if;
  if private.is_conversation_blocked_impl(restored_chat_id) then
    raise exception 'Conversation was still marked personally blocked after global unban';
  end if;
  perform public.send_chat_message(
    extensions.gen_random_uuid(), restored_chat_id, 'text', 'delivery restored'
  );
  request_id := public.send_friend_request(
    '10000000-0000-0000-0000-000000000083'
  );
  perform set_config(
    'request.jwt.claim.sub', '10000000-0000-0000-0000-000000000083', true
  );
  perform set_config(
    'request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000083","role":"authenticated"}', true
  );
  perform public.respond_friend_request(request_id, true);
  if not exists (
    select 1 from public.get_friends_page(null, null, 50) friend
    where friend.id = '10000000-0000-0000-0000-000000000081'::uuid
  ) then
    raise exception 'A request could not be accepted after an unban';
  end if;
end;
$$;

reset role;

rollback;
