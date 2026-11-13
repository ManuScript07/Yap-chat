-- 1000 stale tasks must not fan out to a new installation. All rolls back.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
 ('b3000000-0000-0000-0000-000000000001',false,false,'{}'),
 ('b3000000-0000-0000-0000-000000000002',false,false,'{}');
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
 ('b3100000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values
 ('b3100000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001'),
 ('b3100000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000002');
insert into public.messages(id,conversation_id,sender_id,type,text)
select gen_random_uuid(),'b3100000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001','text','backlog' from generate_series(1,1000);
update public.push_notification_outbox set created_at=now()-interval '1 hour',message_created_at=now()-interval '1 hour'
where conversation_id='b3100000-0000-0000-0000-000000000001';
insert into public.push_devices(user_id,token,registered_at) values
 ('b3000000-0000-0000-0000-000000000002','brand-new-installation-token-001',now());
set local role service_role;
do $$ declare job_id uuid; result jsonb; begin
 if jsonb_array_length(public.get_due_push_notification_ids(100000))>20 then raise exception 'Batch cap bypass'; end if;
 for job_id in select id from public.push_notification_outbox where conversation_id='b3100000-0000-0000-0000-000000000001' loop
   result:=public.claim_push_notification(job_id);
   if result->>'status'<>'no_devices' then raise exception 'Old task targeted new installation'; end if;
 end loop;
 if (select count(*) from public.push_notification_outbox where conversation_id='b3100000-0000-0000-0000-000000000001'
   and status='sent' and delivery_result='no_devices' and attempts=0)<>1000 then raise exception 'Backlog replayed'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.messages where conversation_id='b3100000-0000-0000-0000-000000000001')<>1000 then
   raise exception 'Messages altered by push processing'; end if;
end $$;
select 'PASS: 1000 backlog jobs excluded from new installation; all messages retained';
rollback;
