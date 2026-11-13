begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8650000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,5)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
values('b8650000-0000-0000-0000-000000000001','a8650000-0000-0000-0000-000000000001','a8650000-0000-0000-0000-000000000002','a8650000-0000-0000-0000-000000000002'),
('b8650000-0000-0000-0000-000000000002','a8650000-0000-0000-0000-000000000002','a8650000-0000-0000-0000-000000000003','a8650000-0000-0000-0000-000000000002');
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8650000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8650000-%';
insert into public.messages(id,conversation_id,sender_id,type,text)values
('c8650000-0000-0000-0000-000000000001','b8650000-0000-0000-0000-000000000001','a8650000-0000-0000-0000-000000000002','text','direct preview');
select set_config('request.jwt.claim.sub','a8650000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$declare found jsonb;expected jsonb;begin
 found:=public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');
 select jsonb_agg(to_jsonb(s)) into expected from public.get_chat_summaries_by_ids(array['b8650000-0000-0000-0000-000000000001']::uuid[])s;
 if found is distinct from expected then raise exception 'Peer and ID summaries differ';end if;
 if public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000003')<>'[]'::jsonb then raise exception 'Non-member conversation exposed';end if;
 if public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000005')<>'[]'::jsonb then raise exception 'Conversation created by read';end if;
 if public.get_direct_chat_summary('ffffffff-ffff-ffff-ffff-ffffffffffff')<>'[]'::jsonb then raise exception 'Nonexistent profile exposed';end if;
 begin perform public.get_direct_chat_summary(null);raise exception 'Null peer accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_direct_chat_summary(auth.uid());raise exception 'Self accepted';exception when sqlstate '22023' then null;end;
 begin perform private.consume_chat_summary_refresh_quota(1);raise exception 'Quota helper exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if(select count(*)from public.conversations where id::text like 'b8650000-%')<>2 then raise exception 'Lookup created conversation';end if;
 if(select request_count from private.chat_summary_refresh_quota where user_id=auth.uid())<>5 then raise exception 'Empty/found calls not charged exactly once';end if;
end $$;
update public.conversation_members set hidden_at=now() where conversation_id='b8650000-0000-0000-0000-000000000001' and user_id=auth.uid();
set local role authenticated;
do $$begin if public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002')<>'[]'::jsonb then raise exception 'Hidden chat exposed';end if;end $$;
reset role;
update public.conversation_members set hidden_at=null,is_muted=true where conversation_id='b8650000-0000-0000-0000-000000000001' and user_id=auth.uid();
update public.conversation_members set hidden_at=now() where conversation_id='b8650000-0000-0000-0000-000000000001' and user_id='a8650000-0000-0000-0000-000000000002';
set local role authenticated;
do $$begin if public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002')#>>'{0,is_muted}'<>'true' then raise exception 'Peer hidden state affected actor or lost mute';end if;end $$;
reset role;
savepoint peer_ban;
insert into private.global_account_bans(target_user_id,note)values('a8650000-0000-0000-0000-000000000002','direct lookup test');
set local role authenticated;
do $$declare result jsonb:=public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');begin
 if result#>>'{0,peer_is_globally_banned}'<>'true' or result#>>'{0,peer_username}'<>'' or result#>>'{0,peer_avatar_url}' is not null then raise exception 'Banned peer not redacted';end if;
end $$;
reset role;
rollback to peer_ban;
savepoint peer_deletion;
insert into private.account_deletion_requests(target_user_id,requested_by,note)values('a8650000-0000-0000-0000-000000000002','admin','direct lookup test');
set local role authenticated;
do $$begin if public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002')#>>'{0,peer_is_deleted}'<>'true' then raise exception 'Deleted peer state lost';end if;end $$;
reset role;
rollback to peer_deletion;
update private.chat_summary_refresh_quota set request_count=179,requested_rows=179 where user_id=auth.uid();
set local role authenticated;
select public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');
do $$begin
 begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000003');raise exception 'Empty quota bypass';exception when sqlstate 'PT429' then null;end;
 begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');raise exception 'Found quota bypass';exception when sqlstate 'PT429' then null;end;
 begin perform public.get_chat_summaries_by_ids(array['b8650000-0000-0000-0000-000000000001']::uuid[]);raise exception 'Shared quota bypass';exception when sqlstate 'PT429' then null;end;
end $$;
reset role;
update private.chat_summary_refresh_quota set window_started_at=statement_timestamp()-interval '61 seconds' where user_id=auth.uid();
set local role authenticated;
select public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');
reset role;
update private.chat_summary_refresh_quota set requested_rows=3000 where user_id=auth.uid();
set local role authenticated;
do $$begin begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000003');raise exception 'Shared row quota bypass';exception when sqlstate 'PT429' then null;end;end $$;
reset role;
insert into private.global_account_bans(target_user_id,note)values('a8650000-0000-0000-0000-000000000004','direct actor test');
select set_config('request.jwt.claim.sub','a8650000-0000-0000-0000-000000000004',true);
set local role authenticated;
do $$begin begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');raise exception 'Banned actor accepted';exception when sqlstate 'P0001' then if sqlerrm<>'account_globally_banned' then raise;end if;end;end $$;
reset role;
insert into private.account_deletion_requests(target_user_id,requested_by,note)values('a8650000-0000-0000-0000-000000000005','admin','direct actor test');
select set_config('request.jwt.claim.sub','a8650000-0000-0000-0000-000000000005',true);
set local role authenticated;
do $$begin begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');raise exception 'Pending actor accepted';exception when sqlstate 'P0001' then if sqlerrm<>'account_pending_deletion' then raise;end if;end;end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$begin begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');raise exception 'No auth accepted';exception when sqlstate '28000' then null;end;end $$;
reset role;
set local role anon;
do $$begin begin perform public.get_direct_chat_summary('a8650000-0000-0000-0000-000000000002');raise exception 'Anon accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
rollback;
