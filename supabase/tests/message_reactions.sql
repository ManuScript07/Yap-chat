-- Local Supabase only. No fixture survives rollback.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
 ('a4000000-0000-0000-0000-000000000001',false,false,'{}'),
 ('a4000000-0000-0000-0000-000000000002',false,false,'{}'),
 ('a4000000-0000-0000-0000-000000000003',false,false,'{}');
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
 ('a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002','a4000000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values
 ('a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001'),
 ('a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002');
insert into public.messages(id,conversation_id,sender_id,type,text) values
 ('a4200000-0000-0000-0000-000000000001','a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','text','hello');
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000002',true);
set local role authenticated;
do $$ declare result jsonb; begin
 result := public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','heart','a4300000-0000-0000-0000-000000000001',0);
 if result->'state'->>'version' <> '1' or result->>'applied' <> 'true' then raise exception 'First reaction failed: %',result; end if;
 result := public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','heart','a4300000-0000-0000-0000-000000000001',0);
 if result->'state'->>'version' <> '1' then raise exception 'Replay was not idempotent'; end if;
 result := public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','fire','a4300000-0000-0000-0000-000000000002',0);
 if result->>'applied' <> 'false' then raise exception 'Stale device overwrote reaction'; end if;
 begin
  perform public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','custom','a4300000-0000-0000-0000-000000000003',1);
  raise exception 'Arbitrary reaction accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','fire','a4300000-0000-0000-0000-000000000003',1);
  raise exception 'Rapid write accepted';
 exception when sqlstate '42901' then null; end;
 if (select count(*) from public.get_conversation_messages('a4100000-0000-0000-0000-000000000001') where reaction_state->>'version'='1') <> 1 then raise exception 'Page projection lost reaction'; end if;
 if (select count(*) from public.get_conversation_message_window('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001') where reaction_state->>'version'='1') <> 1 then raise exception 'Window lost reaction'; end if;
 if (select count(*) from public.get_visible_conversation_message_states('a4100000-0000-0000-0000-000000000001',array['a4200000-0000-0000-0000-000000000001']::uuid[]) where reaction_state->>'version'='1') <> 1 then raise exception 'Cached page lost reaction'; end if;
 begin
  perform public.get_visible_conversation_message_states('a4100000-0000-0000-0000-000000000001',array_fill('a4200000-0000-0000-0000-000000000001'::uuid,array[61]));
  raise exception 'Oversized page accepted';
 exception when invalid_parameter_value then null; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.push_notification_outbox where notification_type='message_reaction' and reaction_message_id='a4200000-0000-0000-0000-000000000001') <> 1 then raise exception 'First reaction push missing/duplicated'; end if;
 if has_function_privilege('anon','public.set_message_reaction(uuid,uuid,text,uuid,bigint)','EXECUTE') then raise exception 'Anonymous write allowed'; end if;
 if (select prosecdef from pg_proc where oid='public.set_message_reaction(uuid,uuid,text,uuid,bigint)'::regprocedure) then raise exception 'Exposed RPC uses definer'; end if;
end $$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','heart','a4300000-0000-0000-0000-000000000004',0);
reset role;
do $$ begin
 if (select jsonb_array_length(private.message_reaction_state('a4200000-0000-0000-0000-000000000001')->'reactions')) <> 2 then raise exception 'Both participants must retain choices'; end if;
 if (select count(*) from public.push_notification_outbox where notification_type='message_reaction' and reaction_message_id='a4200000-0000-0000-0000-000000000001') <> 1 then raise exception 'Own message produced push'; end if;
 if exists(select 1 from public.message_receipts where message_id='a4200000-0000-0000-0000-000000000001') then raise exception 'Reaction changed receipts'; end if;
end $$;
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second';
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001',null,'a4300000-0000-0000-0000-000000000005',1);
reset role;
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second';
set local role authenticated;
select public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','poop','a4300000-0000-0000-0000-000000000006',3);
reset role;
do $$ begin
 if (select count(*) from public.push_notification_outbox where notification_type='message_reaction' and reaction_message_id='a4200000-0000-0000-0000-000000000001') <> 1 then raise exception 'Re-add duplicated push'; end if;
end $$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000003',true);
set local role authenticated;
do $$ begin
 begin
  perform public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','heart',gen_random_uuid(),0);
  raise exception 'Nonmember write allowed';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from public.get_visible_conversation_message_states('a4100000-0000-0000-0000-000000000001',array['a4200000-0000-0000-0000-000000000001']::uuid[])) then raise exception 'Nonmember read allowed'; end if;
end $$;
reset role;

-- Guard all protected account/message states, including both block directions.
create function pg_temp.expect_reaction_error(expected_state text) returns void
language plpgsql security invoker as $$ begin
 begin
  perform public.set_message_reaction('a4100000-0000-0000-0000-000000000001','a4200000-0000-0000-0000-000000000001','fire',gen_random_uuid(),4);
 exception when others then
  if sqlstate = expected_state then return; end if;
  raise;
 end;
 raise exception 'Expected reaction denial %',expected_state;
end $$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000002',true);
insert into public.user_blocks(blocker_user_id,blocked_user_id) values
 ('a4000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
delete from public.user_blocks where blocker_user_id='a4000000-0000-0000-0000-000000000001';
insert into public.user_blocks(blocker_user_id,blocked_user_id) values
 ('a4000000-0000-0000-0000-000000000002','a4000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
delete from public.user_blocks where blocker_user_id='a4000000-0000-0000-0000-000000000002';
insert into private.global_account_bans(target_user_id,note) values ('a4000000-0000-0000-0000-000000000001','reaction test');
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
update private.global_account_bans set revoked_at=statement_timestamp() where target_user_id='a4000000-0000-0000-0000-000000000001';
insert into private.account_deletion_requests(target_user_id,requested_by,note) values
 ('a4000000-0000-0000-0000-000000000001','admin','reaction test');
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
update private.account_deletion_requests set restored_at=statement_timestamp() where target_user_id='a4000000-0000-0000-0000-000000000001';
insert into public.message_hidden_for_users(message_id,user_id) values ('a4200000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
delete from public.message_hidden_for_users where user_id='a4000000-0000-0000-0000-000000000002';
update public.conversation_members set cleared_at=statement_timestamp() where user_id='a4000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
update public.conversation_members set cleared_at=null where user_id='a4000000-0000-0000-0000-000000000002';
update private.message_reaction_write_limits set request_count=60 where user_id='a4000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.expect_reaction_error('42901');
reset role;
update private.message_reaction_write_limits set request_count=1 where user_id='a4000000-0000-0000-0000-000000000002';

-- All message types share the same reaction transport. Muting suppresses push.
insert into public.messages(id,conversation_id,sender_id,type,text,latitude,longitude) values
 ('a4200000-0000-0000-0000-000000000004','a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','image','',null,null),
 ('a4200000-0000-0000-0000-000000000005','a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','audio','',null,null),
 ('a4200000-0000-0000-0000-000000000006','a4100000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','location','',50,30);
update public.conversation_members set is_muted=true where user_id='a4000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_message_reaction('a4100000-0000-0000-0000-000000000001',id,'cry',gen_random_uuid(),0)
from public.messages where id in ('a4200000-0000-0000-0000-000000000004','a4200000-0000-0000-0000-000000000005','a4200000-0000-0000-0000-000000000006');
reset role;
do $$ begin
 if exists(select 1 from public.push_notification_outbox where notification_type='message_reaction' and reaction_message_id in ('a4200000-0000-0000-0000-000000000004','a4200000-0000-0000-0000-000000000005','a4200000-0000-0000-0000-000000000006')) then raise exception 'Muted chat produced reaction push'; end if;
 if (select count(*) from private.message_reactions where message_id in ('a4200000-0000-0000-0000-000000000004','a4200000-0000-0000-0000-000000000005','a4200000-0000-0000-0000-000000000006')) <> 3 then raise exception 'Some media type lost reaction'; end if;
 if (select count(*) from realtime.messages where payload->>'reason'='reaction_changed' and payload->>'message_id'='a4200000-0000-0000-0000-000000000001') <> 8 then raise exception 'Reaction must broadcast only one event per participant per real change'; end if;
end $$;
update public.messages set deleted_for_everyone_at=statement_timestamp() where id='a4200000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.expect_reaction_error('42501');
reset role;
-- Purging a message clears reaction rows and push jobs as well.
delete from public.messages where id='a4200000-0000-0000-0000-000000000001';
do $$ begin
 if exists(select 1 from private.message_reactions where message_id='a4200000-0000-0000-0000-000000000001') or exists(select 1 from private.message_reaction_versions where message_id='a4200000-0000-0000-0000-000000000001') or exists(select 1 from public.push_notification_outbox where reaction_message_id='a4200000-0000-0000-0000-000000000001') then raise exception 'Reaction metadata survived purge'; end if;
end $$;
-- Finalizing an account still hides authored messages; reactions must not
-- prevent the established account-deletion lifecycle or resurrect push jobs.
insert into private.account_deletion_requests(target_user_id,requested_by,note)
values ('a4000000-0000-0000-0000-000000000001','admin','reaction finalization test');
update private.account_deletion_requests set requested_at='1899-12-01T00:00:00Z', scheduled_for='1900-01-01T00:00:00Z'
where target_user_id='a4000000-0000-0000-0000-000000000001'
  and restored_at is null and finalized_at is null;
select private.finalize_due_account_deletions(1);
do $$ begin
 if not exists(select 1 from private.account_deletion_requests
   where target_user_id='a4000000-0000-0000-0000-000000000001' and finalized_at is not null)
   then raise exception 'Reaction metadata prevented account finalization'; end if;
 if exists(select 1 from public.messages
   where sender_id='a4000000-0000-0000-0000-000000000001' and deleted_for_everyone_at is null)
   then raise exception 'Finalized author retained visible messages'; end if;
 if public.is_push_reaction_deliverable('a4200000-0000-0000-0000-000000000004',
   'a4000000-0000-0000-0000-000000000002','cry')
   then raise exception 'Finalized author retained a deliverable reaction'; end if;
end $$;
rollback;
