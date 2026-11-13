-- Compare the new bounded RPC with the installed legacy contract, atomically.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8510000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'
from generate_series(1,54) i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('b8510000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'a8510000-0000-0000-0000-000000000001',
 ('a8510000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,
 'a8510000-0000-0000-0000-000000000001' from generate_series(1,51) i;
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8510000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8510000-%';
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select ('c8510000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'b8510000-0000-0000-0000-000000000001',
 case when i=4 then 'a8510000-0000-0000-0000-000000000001'::uuid else 'a8510000-0000-0000-0000-000000000002'::uuid end,
 'text','fixture '||i,'2020-01-01'::timestamptz+i*interval '1 day' from generate_series(1,5) i;
update public.conversation_members set cleared_at='2020-01-02',last_read_at='2025-01-01',is_muted=true
 where conversation_id='b8510000-0000-0000-0000-000000000001' and user_id='a8510000-0000-0000-0000-000000000001';
insert into public.message_receipts values('c8510000-0000-0000-0000-000000000003','a8510000-0000-0000-0000-000000000001',now());
insert into public.message_hidden_for_users(message_id,user_id) values('c8510000-0000-0000-0000-000000000005','a8510000-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ declare batch_ids uuid[]; actual jsonb; expected jsonb; begin
  select array_agg(('b8510000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid) into batch_ids from generate_series(1,50) i;
  select jsonb_agg(to_jsonb(s) order by s.id) into expected from public.get_chat_summaries() s where s.id=any(batch_ids);
  select jsonb_agg(to_jsonb(s) order by s.id) into actual from public.get_chat_summaries_by_ids(batch_ids) s;
  if actual is distinct from expected then raise exception 'Legacy summary contract mismatch'; end if;
  if (select unread_count from public.get_chat_summaries_by_ids(batch_ids) where id='b8510000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Selective read hole lost'; end if;
  if (select count(*) from public.get_chat_summaries_by_ids(array[batch_ids[1],batch_ids[1]]))<>1 then raise exception 'Duplicate row'; end if;
end $$;
-- Explicit invalid shapes, including null/empty and >50 raw elements.
do $$ begin
 begin perform public.get_chat_summaries_by_ids(null); raise exception 'null accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.get_chat_summaries_by_ids(array[]::uuid[]); raise exception 'empty accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.get_chat_summaries_by_ids(array[null]::uuid[]); raise exception 'null element accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.get_chat_summaries_by_ids(array_fill('b8510000-0000-0000-0000-000000000001'::uuid,array[51])); raise exception '51 accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.get_chat_summaries_by_ids(array[['b8510000-0000-0000-0000-000000000001'::uuid]]); raise exception 'matrix accepted'; exception when sqlstate '22023' then null; end;
end $$;
reset role;
-- Hidden rows and deleted latest messages preserve legacy behavior.
update public.conversation_members set hidden_at=now() where user_id='a8510000-0000-0000-0000-000000000001' and conversation_id='b8510000-0000-0000-0000-000000000002';
update public.messages set deleted_for_everyone_at=now() where id='c8510000-0000-0000-0000-000000000004';
set local role authenticated;
do $$ declare actual jsonb; expected jsonb; begin
 select jsonb_agg(to_jsonb(s) order by s.id) into expected from public.get_chat_summaries() s where s.id in('b8510000-0000-0000-0000-000000000001','b8510000-0000-0000-0000-000000000002');
 select jsonb_agg(to_jsonb(s) order by s.id) into actual from public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001','b8510000-0000-0000-0000-000000000002']::uuid[]) s;
 if actual is distinct from expected then raise exception 'Hide/delete summary mismatch'; end if;
 perform public.block_user('a8510000-0000-0000-0000-000000000002');
end $$;
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000002',true);
do $$ declare a jsonb; b jsonb; begin
 select to_jsonb(s) into a from public.get_chat_summaries() s;
 select to_jsonb(s) into b from public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]) s;
 if a is distinct from b or b->>'peer_username'<>'' or b->>'blocked_by_peer'<>'true' then raise exception 'Block redaction mismatch'; end if;
end $$;
reset role;
-- Global-ban and pending-deletion presentation must match the legacy wrapper.
insert into private.global_account_bans(target_user_id,note) values('a8510000-0000-0000-0000-000000000002','summary peer');
insert into private.account_deletion_requests(target_user_id,requested_by,note) values('a8510000-0000-0000-0000-000000000004','admin','summary peer');
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ declare a jsonb;b jsonb;begin
 select jsonb_agg(to_jsonb(s) order by s.id) into a from public.get_chat_summaries() s where s.id in('b8510000-0000-0000-0000-000000000001','b8510000-0000-0000-0000-000000000003');
 select jsonb_agg(to_jsonb(s) order by s.id) into b from public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001','b8510000-0000-0000-0000-000000000003']::uuid[]) s;
 if a is distinct from b then raise exception 'Banned/deleted peer presentation mismatch';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000054',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[])) then raise exception 'Non-member exposed'; end if;
 begin perform * from private.chat_summary_refresh_quota; raise exception 'Quota exposed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Both budgets are independent of the legacy full-list quota.
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000001',true);
update private.chat_summary_refresh_quota set request_count=180 where user_id=auth.uid();
set local role authenticated;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'Call quota bypass'; exception when sqlstate 'PT429' then null; end;
 perform public.get_chat_summaries();
end $$;
reset role;
update private.chat_summary_refresh_quota set request_count=1,requested_rows=3000 where user_id=auth.uid();
set local role authenticated;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'Row quota bypass'; exception when sqlstate 'PT429' then null; end;
end $$;
reset role;
update private.chat_summary_refresh_quota set window_started_at=statement_timestamp()-interval '61 seconds' where user_id=auth.uid();
set local role authenticated;
select count(*) from public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]);
reset role;
insert into private.global_account_bans(target_user_id,note) values('a8510000-0000-0000-0000-000000000054','summary guard');
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000054',true);
set local role authenticated;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'Ban bypass'; exception when sqlstate 'P0001' then if sqlerrm<>'account_globally_banned' then raise; end if; end;
end $$;
reset role;
insert into private.account_deletion_requests(target_user_id,requested_by,note) values('a8510000-0000-0000-0000-000000000053','admin','summary actor guard');
select set_config('request.jwt.claim.sub','a8510000-0000-0000-0000-000000000053',true);
set local role authenticated;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'Pending actor bypass'; exception when sqlstate 'P0001' then if sqlerrm<>'account_pending_deletion' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'No identity accepted'; exception when sqlstate '28000' then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.get_chat_summaries_by_ids(array['b8510000-0000-0000-0000-000000000001']::uuid[]); raise exception 'Anonymous execution granted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
