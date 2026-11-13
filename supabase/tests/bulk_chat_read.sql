-- Local atomic contract; all profiles, messages, receipts and events roll back.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('b6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'::jsonb
from generate_series(1,53) i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('c6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'b6500000-0000-0000-0000-000000000001',
 ('b6500000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,
 'b6500000-0000-0000-0000-000000000001' from generate_series(1,51) i;
insert into public.conversation_members(conversation_id,user_id,last_read_at)
select id,user_one_id,'2026-01-01'::timestamptz from public.conversations where id::text like 'c6500000-%'
union all
select id,user_two_id,'2026-01-01'::timestamptz from public.conversations where id::text like 'c6500000-%';
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select ('d6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('c6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('b6500000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,
 'text','old unread hole','2020-01-01' from generate_series(1,51) i;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values
 ('d6500000-0000-0000-0000-000000000101','c6500000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000002','text','already read','2021-01-01'),
 ('d6500000-0000-0000-0000-000000000102','c6500000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000002','text','hidden','2021-01-01'),
 ('d6500000-0000-0000-0000-000000000103','c6500000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000002','text','deleted','2021-01-01'),
 ('d6500000-0000-0000-0000-000000000104','c6500000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000001','text','mine','2021-01-01'),
 ('d6500000-0000-0000-0000-000000000105','c6500000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000002','text','cleared','1998-01-01');
insert into public.message_receipts values
 ('d6500000-0000-0000-0000-000000000101','b6500000-0000-0000-0000-000000000001','2022-01-01');
insert into public.message_hidden_for_users(message_id,user_id) values
 ('d6500000-0000-0000-0000-000000000102','b6500000-0000-0000-0000-000000000001');
update public.messages set deleted_for_everyone_at=now() where id='d6500000-0000-0000-0000-000000000103';
update public.conversation_members set cleared_at='1999-01-01'
 where user_id='b6500000-0000-0000-0000-000000000001';
update public.conversation_members set last_read_at='2040-01-01'
 where user_id='b6500000-0000-0000-0000-000000000001'
   and conversation_id='c6500000-0000-0000-0000-000000000002';
create temp table read_members_before as select *,to_jsonb(cm)-'last_read_at' as other_fields
 from public.conversation_members cm where conversation_id::text like 'c6500000-%';
select set_config('request.jwt.claim.sub','b6500000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.mark_conversations_read(array(select ('c6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,50) i));
reset role;
do $$ begin
 if (select count(*) from public.message_receipts where user_id='b6500000-0000-0000-0000-000000000001')<>51 then
   raise exception 'Wrong receipts: lost unread holes or marked excluded/unselected rows'; end if;
 if exists(select 1 from public.message_receipts where message_id::text like 'd6500000-%'
   and user_id<>'b6500000-0000-0000-0000-000000000001') then
   raise exception 'Another user receipts changed'; end if;
 if (select read_at from public.message_receipts where message_id='d6500000-0000-0000-0000-000000000101')<>'2022-01-01'::timestamptz then
   raise exception 'Existing receipt timestamp changed'; end if;
 if (select last_read_at from public.conversation_members where conversation_id='c6500000-0000-0000-0000-000000000002'
   and user_id='b6500000-0000-0000-0000-000000000001')<>'2040-01-01'::timestamptz then
   raise exception 'Read metadata moved backwards'; end if;
 if (select count(*) from realtime.messages where payload->>'reason'='read' and payload->>'conversation_id' like 'c6500000-%')<>100 then
   raise exception 'Expected exactly two existing private events per changed chat'; end if;
 if exists(select 1 from realtime.messages where payload->>'reason'='read' and payload->>'conversation_id' like 'c6500000-%'
   and (not private or event<>'changed' or topic not like 'user:b6500000-%:chats')) then
   raise exception 'Read event leaked'; end if;
 if exists(select 1 from read_members_before b join public.conversation_members cm using(conversation_id,user_id)
   where b.other_fields is distinct from to_jsonb(cm)-'last_read_at') then
   raise exception 'Unrelated member fields changed'; end if;
 if (select request_count from private.chat_bulk_action_write_limits
   where user_id='b6500000-0000-0000-0000-000000000001' and action_name='mark_read')<>1 then
   raise exception 'Batch charged quota per chat'; end if;
end $$;
create temp table read_members_after as select * from public.conversation_members where conversation_id::text like 'c6500000-%';
set local role authenticated;
select public.mark_conversations_read(array(select ('c6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,50) i));
select public.mark_conversations_read(array_fill('c6500000-0000-0000-0000-000000000001'::uuid,array[50]));
do $$ declare ids uuid[]; begin
 foreach ids slice 1 in array array[
   array['c6500000-0000-0000-0000-000000000001'::uuid,null],array[null::uuid,null]
 ] loop
   begin perform public.mark_conversations_read(ids); raise exception 'Null entry accepted';
   exception when invalid_parameter_value then null; end;
 end loop;
 begin perform public.mark_conversations_read(null); raise exception 'Null accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.mark_conversations_read('{}'); raise exception 'Empty accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.mark_conversations_read(array_fill('c6500000-0000-0000-0000-000000000001'::uuid,array[51])); raise exception '51 accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.mark_conversations_read(array_fill('c6500000-0000-0000-0000-000000000001'::uuid,array[2,2])); raise exception '2D accepted'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
do $$ begin
 if exists((select * from public.conversation_members where conversation_id::text like 'c6500000-%') except select * from read_members_after) then
   raise exception 'No-op updated member state'; end if;
 if (select count(*) from realtime.messages where payload->>'reason'='read' and payload->>'conversation_id' like 'c6500000-%')<>100 then
   raise exception 'No-op emitted extra events'; end if;
 if (select prosecdef from pg_proc where oid='public.mark_conversations_read(uuid[])'::regprocedure)
   or has_function_privilege('anon','public.mark_conversations_read(uuid[])','EXECUTE') then
   raise exception 'Public wrapper privilege changed'; end if;
end $$;
-- A nonmember cannot read any messages; no extra event.
select set_config('request.jwt.claim.sub','b6500000-0000-0000-0000-000000000053',true);
set local role authenticated;
select public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000051']::uuid[]);
reset role;
do $$ begin
 if exists(select 1 from public.message_receipts where user_id='b6500000-0000-0000-0000-000000000053') then raise exception 'Nonmember read'; end if;
end $$;
-- No-op calls still consume the existing 20/min quota.
select set_config('request.jwt.claim.sub','b6500000-0000-0000-0000-000000000001',true);
-- First read fast path, with 50 different chats and no pre-existing receipts.
savepoint first_account_read;
delete from public.message_receipts where user_id='b6500000-0000-0000-0000-000000000001';
set local role authenticated;
select public.mark_conversations_read(array(select ('c6500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,50) i));
reset role;
do $$ begin
 if (select count(*) from public.message_receipts where user_id='b6500000-0000-0000-0000-000000000001')<>51 then
   raise exception 'First read path skipped chats or included excluded rows'; end if;
end $$;
rollback to first_account_read;
update private.chat_bulk_action_write_limits set request_count=19
 where user_id='b6500000-0000-0000-0000-000000000001' and action_name='mark_read';
set local role authenticated;
select public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000001']::uuid[]);
do $$ begin
 begin perform public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000001']::uuid[]);
   raise exception 'Quota bypassed'; exception when sqlstate 'P0001' then
   if sqlerrm<>'chat_bulk_action_rate_limited' then raise; end if; end;
end $$;
reset role;
insert into private.global_account_bans(target_user_id,note) values ('b6500000-0000-0000-0000-000000000053','local bulk read guard');
select set_config('request.jwt.claim.sub','b6500000-0000-0000-0000-000000000053',true);
set local role authenticated;
do $$ begin
 begin perform public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000001']::uuid[]);
   raise exception 'Banned read accepted'; exception when sqlstate 'P0001' then if sqlerrm<>'account_globally_banned' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','b6500000-0000-0000-0000-000000000052',true);
insert into private.account_deletion_requests(target_user_id,requested_by,note) values ('b6500000-0000-0000-0000-000000000052','admin','local bulk read guard');
set local role authenticated;
do $$ begin
 begin perform public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000051']::uuid[]);
   raise exception 'Pending read accepted'; exception when sqlstate 'P0001' then if sqlerrm<>'account_pending_deletion' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
 begin perform public.mark_conversations_read(array['c6500000-0000-0000-0000-000000000001']::uuid[]);
   raise exception 'Missing identity accepted'; exception when sqlstate 'P0001' then if sqlerrm<>'authentication_required' then raise; end if; end;
end $$;
reset role;
rollback;
