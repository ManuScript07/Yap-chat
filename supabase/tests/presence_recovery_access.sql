begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000008101', false, false, '{"name":"Presence diagnostic A"}'),
  ('10000000-0000-0000-0000-000000008102', false, false, '{"name":"Presence diagnostic B"}');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008102', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000008102","role":"authenticated"}', true);
set local role authenticated;
select public.touch_my_presence_session('20000000-0000-0000-0000-000000008102');
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008101', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000008101","role":"authenticated"}', true);
set local role authenticated;
select public.touch_my_presence_session('20000000-0000-0000-0000-000000008101');

do $$
declare
  rejected boolean := false;
  targets uuid[];
begin
  begin
    perform public.set_my_presence_watch_scope(
      '20000000-0000-0000-0000-000000008102', 'foreign-session', '{}'::uuid[]);
  exception when insufficient_privilege then
    rejected := sqlerrm = 'presence_session_inactive';
  end;
  if not rejected then raise exception 'Foreign presence session was accepted'; end if;

  select array_agg(('30000000-0000-0000-0000-' || lpad(value::text,12,'0'))::uuid)
  into targets from generate_series(1,101) value;
  rejected := false;
  begin
    perform public.set_my_presence_watch_scope(
      '20000000-0000-0000-0000-000000008101', 'oversize', targets);
  exception when invalid_parameter_value then
    rejected := sqlerrm = 'presence_scope_too_large';
  end;
  if not rejected then raise exception 'Scope with 101 targets was accepted'; end if;

  for attempt in 1..30 loop
    perform public.set_my_presence_watch_scope(
      '20000000-0000-0000-0000-000000008101', 'quota', '{}'::uuid[]);
  end loop;
  rejected := false;
  begin
    perform public.set_my_presence_watch_scope(
      '20000000-0000-0000-0000-000000008101', 'quota', '{}'::uuid[]);
  exception when sqlstate '42901' then
    rejected := sqlerrm = 'presence_rate_limited';
  end;
  if not rejected then raise exception 'Scope quota did not reject request 31'; end if;

  -- The initial heartbeat already consumed one of the ten allowed requests.
  for attempt in 1..9 loop
    perform public.touch_my_presence_session('20000000-0000-0000-0000-000000008101');
  end loop;
  rejected := false;
  begin
    perform public.touch_my_presence_session('20000000-0000-0000-0000-000000008101');
  exception when sqlstate '42901' then
    rejected := sqlerrm = 'presence_rate_limited';
  end;
  if not rejected then raise exception 'Heartbeat quota did not reject request 11'; end if;

  -- Closing another user's session ID must not close their lease.
  perform public.close_my_presence_session('20000000-0000-0000-0000-000000008102');
end;
$$;
reset role;

do $$
begin
  if not exists (select 1 from private.user_presence_sessions
    where user_id='10000000-0000-0000-0000-000000008102'
      and session_id='20000000-0000-0000-0000-000000008102') then
    raise exception 'Foreign presence lease was removed';
  end if;
  if has_function_privilege('anon', 'public.touch_my_presence_session(uuid)', 'execute')
    or has_function_privilege('anon', 'public.set_my_presence_watch_scope(uuid,text,uuid[])', 'execute')
    or has_function_privilege('anon', 'public.close_my_presence_session(uuid)', 'execute') then
    raise exception 'Anonymous role can execute presence RPCs';
  end if;
  if has_table_privilege('authenticated', 'private.user_presence_sessions', 'select')
    or has_table_privilege('authenticated', 'private.user_presence_watch_targets', 'select') then
    raise exception 'Authenticated role can directly enumerate presence';
  end if;
end;
$$;

-- Legitimate friends observe online before blocking.
insert into public.friendships(user_one_id, user_two_id) values
  ('10000000-0000-0000-0000-000000008101','10000000-0000-0000-0000-000000008102');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008102', true);
set local role authenticated;
do $$
begin
  if not exists (select 1 from public.get_friends_page(null,null,50)
    where id='10000000-0000-0000-0000-000000008101' and is_online) then
    raise exception 'Legitimate friend online was lost';
  end if;
end; $$;
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008101', true);
set local role authenticated;
do $$
declare rejected boolean := false;
begin
  begin
    insert into public.user_blocks(blocker_user_id,blocked_user_id) values
      ('10000000-0000-0000-0000-000000008101','10000000-0000-0000-0000-000000008102');
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Direct block INSERT bypass still allowed'; end if;
  rejected := false;
  begin
    delete from public.user_blocks where blocker_user_id=auth.uid();
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Direct unblock bypass still allowed'; end if;
  perform public.block_user('10000000-0000-0000-0000-000000008102');
  perform public.block_user('10000000-0000-0000-0000-000000008102');
  if not exists (select 1 from public.user_blocks where blocker_user_id=auth.uid()) then
    raise exception 'Normal block RPC / own block list failed';
  end if;
end; $$;
reset role;
do $$
begin
  if exists (select 1 from public.friendships
    where user_one_id='10000000-0000-0000-0000-000000008101'
    and user_two_id='10000000-0000-0000-0000-000000008102') then
    raise exception 'Normal block did not clear friendship';
  end if;
end; $$;

-- Legacy inconsistent friendship: read protection must not rely on cleanup.
insert into public.friendships(user_one_id,user_two_id) values
  ('10000000-0000-0000-0000-000000008101','10000000-0000-0000-0000-000000008102');
insert into auth.users (id,is_sso_user,is_anonymous,raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000008103',false,false,'{"name":"Hidden friend"}'),
  ('10000000-0000-0000-0000-000000008104',false,false,'{"name":"Visible friend"}'),
  ('10000000-0000-0000-0000-000000008105',false,false,'{"name":"Visible friend 2"}');
insert into public.friendships(user_one_id,user_two_id) values
  ('10000000-0000-0000-0000-000000008102','10000000-0000-0000-0000-000000008103'),
  ('10000000-0000-0000-0000-000000008102','10000000-0000-0000-0000-000000008104'),
  ('10000000-0000-0000-0000-000000008102','10000000-0000-0000-0000-000000008105');
insert into public.user_blocks(blocker_user_id,blocked_user_id) values
  ('10000000-0000-0000-0000-000000008103','10000000-0000-0000-0000-000000008102');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008102', true);
set local role authenticated;
do $$
declare first_page record; second_page record; blocked_online boolean;
begin
  if exists (select 1 from public.get_friends_page(null,null,50)
    where id in ('10000000-0000-0000-0000-000000008101','10000000-0000-0000-0000-000000008103')) then
    raise exception 'Legacy block exposes friend identity/presence';
  end if;
  if exists (select 1 from public.get_current_friend('10000000-0000-0000-0000-000000008101'))
    or exists (select 1 from public.get_current_friends(array['10000000-0000-0000-0000-000000008101'::uuid])) then
    raise exception 'Sibling friend refresh exposed blocker';
  end if;
  select * into first_page from public.get_friends_page(null,null,1);
  if first_page.id <> '10000000-0000-0000-0000-000000008105' or
      first_page.total_count <> 2 or not first_page.has_more then
    raise exception 'Filtered first page/count is incorrect';
  end if;
  select * into second_page from public.get_friends_page(first_page.friends_since,first_page.id,1);
  if second_page.id <> '10000000-0000-0000-0000-000000008104' or
      second_page.total_count <> 2 or second_page.has_more then
    raise exception 'Filtered cursor page is incorrect';
  end if;
  select is_online into blocked_online from public.set_my_presence_watch_scope(
    '20000000-0000-0000-0000-000000008102','blocked',
    array['10000000-0000-0000-0000-000000008101'::uuid]);
  if blocked_online is distinct from false then
    raise exception 'Blocked watcher received online status';
  end if;
end; $$;
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000008101', true);
set local role authenticated;
select public.unblock_user('10000000-0000-0000-0000-000000008102');
do $$
begin
  if exists (select 1 from public.user_blocks where blocker_user_id=auth.uid()) then
    raise exception 'Normal unblock RPC failed after revoking direct writes';
  end if;
end; $$;
reset role;
rollback;
