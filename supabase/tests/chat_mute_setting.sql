-- Local, transactional contract: user isolation, idempotency, exact broadcasts,
-- legacy compatibility, validation and a shared server write quota.
begin;
create temp table mute_seen_events(id uuid primary key);
create function pg_temp.expect_mute_events(owner_id uuid, expected_ids uuid[])
returns void language plpgsql as $$
declare actual_count integer; actual_ids uuid[];
begin
  select count(*) into actual_count from realtime.messages e
  where e.payload->>'reason' = 'muted'
    and e.topic like 'user:98000000-%:chats'
    and not exists(select 1 from mute_seen_events s where s.id=e.id);
  if actual_count <> (case when cardinality(expected_ids)>0 then 1 else 0 end) then
    raise exception 'Unexpected number of mute broadcasts: %', actual_count;
  end if;
  if actual_count > 0 then
    select array(select jsonb_array_elements_text(e.payload->'conversation_ids')::uuid)
    into actual_ids from realtime.messages e
    where e.payload->>'reason'='muted' and e.topic='user:'||owner_id::text||':chats'
      and not exists(select 1 from mute_seen_events s where s.id=e.id)
      and e.event='changed' and e.private;
    if actual_ids is distinct from expected_ids then
      raise exception 'Wrong owner, privacy or IDs: got %, expected %', actual_ids, expected_ids;
    end if;
  end if;
  insert into mute_seen_events select id from realtime.messages
    where payload->>'reason'='muted' on conflict do nothing;
end;
$$;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('98000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'::jsonb
from generate_series(1,51) i;
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
('99000000-0000-0000-0000-000000000001','98000000-0000-0000-0000-000000000001','98000000-0000-0000-0000-000000000002','98000000-0000-0000-0000-000000000001'),
('99000000-0000-0000-0000-000000000002','98000000-0000-0000-0000-000000000001','98000000-0000-0000-0000-000000000003','98000000-0000-0000-0000-000000000001'),
('99000000-0000-0000-0000-000000000003','98000000-0000-0000-0000-000000000002','98000000-0000-0000-0000-000000000003','98000000-0000-0000-0000-000000000002');
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 '98000000-0000-0000-0000-000000000001',
 ('98000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 '98000000-0000-0000-0000-000000000001'
from generate_series(4,51) i;
insert into public.conversation_members(conversation_id,user_id,is_muted)
select c.id,u.id,c.id='99000000-0000-0000-0000-000000000002'::uuid
  and u.id='98000000-0000-0000-0000-000000000001'::uuid
from public.conversations c join auth.users u on u.id in(c.user_one_id,c.user_two_id)
where c.id::text like '99000000-%';
create temp table mute_members_before as
select conversation_id,user_id,to_jsonb(cm)-'is_muted' other_fields
from public.conversation_members cm where conversation_id::text like '99000000-%';

select set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.set_conversations_muted(array[
 '99000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000002',
 '99000000-0000-0000-0000-000000000003']::uuid[],false);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001',array['99000000-0000-0000-0000-000000000002']::uuid[]);
set local role authenticated;
select public.set_conversations_muted(array['99000000-0000-0000-0000-000000000002']::uuid[],false);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001','{}');
set local role authenticated;
select public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000002']::uuid[],true);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001',array['99000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000002']::uuid[]);
set local role authenticated;
select public.set_conversations_muted(array_fill('99000000-0000-0000-0000-000000000001'::uuid,array[50]),true);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001','{}');
do $$ begin
 if (select count(*) from public.conversation_members where user_id='98000000-0000-0000-0000-000000000001' and is_muted)<>2
 or exists(select 1 from public.conversation_members where conversation_id::text like '99000000-%'
   and user_id<>'98000000-0000-0000-0000-000000000001' and is_muted) then
   raise exception 'Wrong target state or changed another user'; end if;
 if exists(select 1 from mute_members_before b join public.conversation_members cm using(conversation_id,user_id)
   where b.other_fields is distinct from to_jsonb(cm)-'is_muted') then
   raise exception 'Read/visibility fields changed'; end if;
 if has_function_privilege('anon','public.set_conversations_muted(uuid[],boolean)','execute')
 or (select prosecdef from pg_proc where oid='public.set_conversations_muted(uuid[],boolean)'::regprocedure) then
   raise exception 'Unsafe public execute privileges/security'; end if;
end $$;

set local role authenticated;
do $$ declare ids uuid[]; i integer; begin
 for i in 1..3 loop
   ids := case i when 1 then array[null::uuid]
     when 2 then array_fill('99000000-0000-0000-0000-000000000001'::uuid,array[51])
     else array[['99000000-0000-0000-0000-000000000001'::uuid]] end;
   begin perform public.set_conversations_muted(ids,true);
     raise exception 'Invalid array was accepted';
   exception when sqlstate '22023' then null; end;
 end loop;
 begin perform public.set_conversations_muted('{}',true);
   raise exception 'Empty array accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.set_conversations_muted(null,true);
   raise exception 'Null array accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],null);
   raise exception 'Null state accepted'; exception when sqlstate '22023' then null; end;
end $$;
reset role;

-- Exercise the actual maximum fan-out, not merely 50 repeated copies of one ID.
set local role authenticated;
select public.set_conversations_muted(array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,51) i where i<>3),true);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001',array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(4,51) i));
set local role authenticated;
select public.set_conversations_muted(array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,51) i where i<>3),false);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001',array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,51) i where i<>3));
set local role authenticated;
select public.set_conversations_muted(array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,51) i where i<>3),true);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001',array(select ('99000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,51) i where i<>3));

-- Both APIs share the same quota, including idempotent no-op calls.
update private.chat_bulk_action_write_limits set request_count=19
where user_id='98000000-0000-0000-0000-000000000001' and action_name='mute';
set local role authenticated;
select public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],true);
do $$ begin
 begin perform public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],false);
   raise exception 'Quota bypassed'; exception when sqlstate 'P0001' then
   if sqlerrm<>'chat_bulk_action_rate_limited' then raise; end if; end;
 begin perform public.toggle_conversations_mute(array['99000000-0000-0000-0000-000000000001']::uuid[]);
   raise exception 'Legacy quota bypassed'; exception when sqlstate 'P0001' then
   if sqlerrm<>'chat_bulk_action_rate_limited' then raise; end if; end;
end $$;
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000001','{}');
-- Legacy clients retain the toggle contract for their own member only.
select set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.toggle_conversations_mute(array['99000000-0000-0000-0000-000000000001']::uuid[]);
reset role;
select pg_temp.expect_mute_events('98000000-0000-0000-0000-000000000002',array['99000000-0000-0000-0000-000000000001']::uuid[]);

insert into private.global_account_bans(target_user_id,note)
values ('98000000-0000-0000-0000-000000000002','local mute guard test');
set local role authenticated;
do $$ begin
 begin perform public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],false);
   raise exception 'Banned account wrote mute'; exception when sqlstate 'P0001' then
   if sqlerrm<>'account_globally_banned' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000001',true);
insert into private.account_deletion_requests(target_user_id,requested_by,note)
values ('98000000-0000-0000-0000-000000000001','admin','local mute pending guard');
set local role authenticated;
do $$ begin
 begin perform public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],false);
   raise exception 'Pending account wrote mute'; exception when sqlstate 'P0001' then
   if sqlerrm<>'account_pending_deletion' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
 begin perform public.set_conversations_muted(array['99000000-0000-0000-0000-000000000001']::uuid[],false);
   raise exception 'Missing identity accepted'; exception when sqlstate 'P0001' then
   if sqlerrm<>'authentication_required' then raise; end if; end;
end $$;
reset role;
rollback;
