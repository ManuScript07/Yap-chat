-- Local Supabase only; fixtures and cleanup assertions roll back.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
 ('b1000000-0000-0000-0000-000000000001',false,false,'{}'),
 ('b1000000-0000-0000-0000-000000000002',false,false,'{}'),
 ('b1000000-0000-0000-0000-000000000003',false,false,'{}');
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
 ('b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values
 ('b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001'),
 ('b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.set_my_app_language('en');
do $$ begin
 for i in 1..15 loop perform public.register_push_device('push-local-token-'||lpad(i::text,5,'0'),'ru','test'); end loop;
 if (select count(*) from public.push_devices)<>10 then raise exception 'Device cap failed'; end if;
 if exists(select 1 from public.push_devices where locale<>'en') then raise exception 'Saved language lost'; end if;
 begin
   insert into public.push_devices(user_id,token) values(auth.uid(),'direct-insert-token-00001');
   raise exception 'Direct insert bypassed cap';
 exception when insufficient_privilege then null; end;
 begin
   update public.push_devices set enabled=true;
   raise exception 'Direct update accepted';
 exception when insufficient_privilege then null; end;
 begin
   delete from public.push_devices;
   raise exception 'Direct delete accepted';
 exception when insufficient_privilege then null; end;
 begin
   perform public.claim_push_notification(gen_random_uuid());
   raise exception 'Client can claim server jobs';
 exception when insufficient_privilege then null; end;
 begin
   perform public.register_push_device(null);
   raise exception 'NULL token accepted';
 exception when raise_exception then if sqlerrm<>'invalid_push_token' then raise; end if; end;
 for i in 16..60 loop perform public.register_push_device('push-local-token-'||lpad(i::text,5,'0')); end loop;
 begin
   perform public.register_push_device('over-quota-token-000001');
   raise exception 'Quota bypassed';
 exception when sqlstate '42901' then null; end;
end $$;
reset role;
do $$ declare epoch timestamptz; begin
 select registered_at into epoch from public.push_devices where token='push-local-token-00060';
 update private.push_device_write_limits set window_started_at=now()-interval '2 minutes';
 perform public.register_push_device('push-local-token-00060');
 if (select registered_at from public.push_devices where token='push-local-token-00060')<>epoch then
   raise exception 'Foreground refresh reset epoch'; end if;
end $$;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select public.register_push_device('push-local-token-00060');
reset role;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.unregister_push_device('push-local-token-00060');
reset role;
do $$ begin
 if not exists(select 1 from public.push_devices where token='push-local-token-00060' and user_id='b1000000-0000-0000-0000-000000000003') then
   raise exception 'Old owner removed transferred token'; end if;
end $$;
delete from public.push_devices where user_id='b1000000-0000-0000-0000-000000000002';
insert into public.push_devices(id,user_id,token,registered_at) values
 ('b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','delivery-old-token-00001',now()-interval '1 day'),
 ('b1300000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002','delivery-old-token-00002',now()-interval '1 day'),
 ('b1300000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000002','delivery-new-token-00003',now()+interval '1 second');
insert into public.messages(id,conversation_id,sender_id,type,text) values
 ('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','text','hello');
set local role service_role;
do $$ declare job_id uuid; first jsonb; second jsonb; result jsonb; begin
 select id into job_id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000001';
 first:=public.claim_push_notification(job_id);
 if jsonb_array_length(first->'devices')<>2 then raise exception 'New install received old job'; end if;
 if first->'job'->>'attempts'<>'1' then raise exception 'Attempts not DB owned'; end if;
 if public.claim_push_notification(job_id)->>'status'<>'already_processed' then raise exception 'Duplicate claim'; end if;
 result:=public.finish_push_notification(job_id,(first->'job'->>'claim_token')::uuid,
   '[{"device_id":"b1300000-0000-0000-0000-000000000001","token":"delivery-old-token-00001","outcome":"accepted"},
     {"device_id":"b1300000-0000-0000-0000-000000000002","token":"delivery-old-token-00002","outcome":"retry"}]',300,'FCM 429');
 if result->>'status'<>'pending' or result->>'devices'<>'1' then raise exception 'Partial progress lost'; end if;
 if (select next_attempt_at from public.push_notification_outbox where id=job_id)<statement_timestamp()+interval '299 seconds' then
   raise exception 'Retry-After ignored'; end if;
 if public.claim_push_notification(job_id)->>'status'<>'already_processed' then raise exception 'Early retry'; end if;
 update public.push_notification_outbox set next_attempt_at=now()-interval '1 second' where id=job_id;
 second:=public.claim_push_notification(job_id);
 if jsonb_array_length(second->'devices')<>1 or second->'job'->>'attempts'<>'2' then raise exception 'Accepted device resent'; end if;
 update public.push_notification_outbox set lease_until=now()-interval '1 second' where id=job_id;
 first:=public.claim_push_notification(job_id);
 if first->'job'->>'attempts'<>'3' then raise exception 'Expired lease not recovered'; end if;
 if public.finish_push_notification(job_id,(second->'job'->>'claim_token')::uuid,'[]')->>'status'<>'lease_lost' then
   raise exception 'Stale worker overwrote new lease'; end if;
 result:=public.finish_push_notification(job_id,(first->'job'->>'claim_token')::uuid,
   '[{"device_id":"b1300000-0000-0000-0000-000000000002","token":"delivery-old-token-00002","outcome":"invalid"}]');
 if result->>'status'<>'sent' or result->>'devices'<>'1' then raise exception 'Invalid token completion'; end if;
 if (select enabled from public.push_devices where id='b1300000-0000-0000-0000-000000000002') then raise exception 'Invalid token remained enabled'; end if;
end $$;
reset role;

-- Expiry, retry ceiling, muted/deleted messages, blocks, inaccessible accounts.
insert into public.messages(id,conversation_id,sender_id,type,text)
select ('b1200000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','text','state test' from generate_series(2,7) i;
update public.push_notification_outbox set expires_at=now()-interval '1 second' where message_id='b1200000-0000-0000-0000-000000000002';
update public.push_notification_outbox set attempts=8 where message_id='b1200000-0000-0000-0000-000000000003';
update public.messages set deleted_for_everyone_at=now() where id='b1200000-0000-0000-0000-000000000004';
set local role service_role;
do $$ declare result jsonb; begin
 result:=public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000002'));
 if result->>'status'<>'expired' then raise exception 'Expired push sent'; end if;
 result:=public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000003'));
 if result->>'status'<>'failed' then raise exception 'Retry cap failed'; end if;
 result:=public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000004'));
 if result->>'status'<>'message_deleted' then raise exception 'Deleted message sent'; end if;
end $$;
reset role;
update public.conversation_members set is_muted=true where user_id='b1000000-0000-0000-0000-000000000002';
do $$ begin
 if public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000005'))->>'status'<>'message_deleted' then raise exception 'Muted queued push sent'; end if;
end $$;
update public.conversation_members set is_muted=false;
insert into public.user_blocks(blocker_user_id,blocked_user_id) values('b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001');
do $$ begin
 if public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000006'))->>'status'<>'message_deleted' then raise exception 'Blocked push sent'; end if;
end $$;
delete from public.user_blocks where blocker_user_id='b1000000-0000-0000-0000-000000000002';
insert into private.global_account_bans(target_user_id,note) values('b1000000-0000-0000-0000-000000000003','Push fixture');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
do $$ begin
 begin perform public.register_push_device('banned-user-token-000001'); raise exception 'Banned registration accepted';
 exception when raise_exception then if sqlerrm<>'account_globally_banned' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
insert into private.account_deletion_requests(target_user_id,requested_by,note) values('b1000000-0000-0000-0000-000000000002','admin','Push fixture');
set local role authenticated;
do $$ begin
 begin perform public.register_push_device('deleting-user-token-00001'); raise exception 'Deleting registration accepted';
 exception when raise_exception then if sqlerrm<>'account_pending_deletion' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if public.claim_push_notification((select id from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000007'))->>'status'<>'message_deleted' then raise exception 'Deleting recipient got push'; end if;
 -- Only terminal history is removed. Message rows and fresh history survive.
 update public.push_notification_outbox set processed_at=now()-interval '8 days' where message_id='b1200000-0000-0000-0000-000000000002';
 if private.cleanup_push_notification_outbox(1)<>1 then raise exception 'Cleanup failed'; end if;
 if not exists(select 1 from public.messages where id='b1200000-0000-0000-0000-000000000002') then raise exception 'Cleanup removed message'; end if;
 if not exists(select 1 from public.push_notification_outbox where message_id='b1200000-0000-0000-0000-000000000001') then raise exception 'Cleanup removed fresh delivery'; end if;
 if has_function_privilege('anon','public.register_push_device(text,text,text)','EXECUTE') then raise exception 'Anonymous registration'; end if;
 if (select prosecdef from pg_proc where oid='public.register_push_device(text,text,text)'::regprocedure) then raise exception 'Public RPC uses definer'; end if;
end $$;
select 'PASS: push device guards, epoch, partial delivery, retry, lease, expiry, mute, block, deletion and cleanup';
rollback;
