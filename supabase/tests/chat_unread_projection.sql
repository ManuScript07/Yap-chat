begin;
create function pg_temp.assert_unread_projection()returns void language plpgsql set search_path='' as $$
declare mismatches integer;
begin
 with expected as(
  select m.id as message_id,cm.user_id,m.conversation_id,m.created_at
  from public.messages m join public.conversation_members cm on cm.conversation_id=m.conversation_id
  where m.sender_id<>cm.user_id and m.deleted_for_everyone_at is null
   and m.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
   and not exists(select 1 from public.message_receipts r where r.message_id=m.id and r.user_id=cm.user_id)
   and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=cm.user_id)
 ),differences as(
  (select * from expected except select message_id,user_id,conversation_id,created_at from private.chat_unread_messages)
  union all(select message_id,user_id,conversation_id,created_at from private.chat_unread_messages except select * from expected)
 )select count(*)into mismatches from differences;
 if mismatches<>0 then raise exception 'Unread evidence differs by % rows',mismatches;end if;
 with expected as(
  select cm.conversation_id,cm.user_id,cm.hidden_at is null as is_visible,cm.is_muted,count(u.message_id)as unread_count
  from public.conversation_members cm left join private.chat_unread_messages u using(conversation_id,user_id)
  group by cm.conversation_id,cm.user_id,cm.hidden_at,cm.is_muted
 ),differences as(
  (select * from expected except select conversation_id,user_id,is_visible,is_muted,unread_count from private.chat_unread_counts)
  union all(select conversation_id,user_id,is_visible,is_muted,unread_count from private.chat_unread_counts except select * from expected)
 )select count(*)into mismatches from differences;
 if mismatches<>0 then raise exception 'Unread counts/state differ by % rows',mismatches;end if;
end;$$;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select('a8670000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,5)i;
update public.profiles set display_name=case id::text when 'a8670000-0000-0000-0000-000000000002' then 'Alpha' else 'Beta' end where id::text like 'a8670000-%';
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select('b8670000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'a8670000-0000-0000-0000-000000000001',('a8670000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'a8670000-0000-0000-0000-000000000001' from generate_series(1,2)i;
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8670000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8670000-%';
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select('c8670000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('b8670000-0000-0000-0000-'||lpad(case when i<=4 then '1' else '2' end,12,'0'))::uuid,
 case when i in(4,7)then 'a8670000-0000-0000-0000-000000000001'::uuid when i<=4 then 'a8670000-0000-0000-0000-000000000002'::uuid else 'a8670000-0000-0000-0000-000000000003'::uuid end,
 case when i=2 then 'image' when i=3 then 'audio' else 'text' end,'unread fixture','2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,7)i;
select pg_temp.assert_unread_projection();
select set_config('request.jwt.claim.sub','a8670000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$declare total bigint;page jsonb;state jsonb;begin
 state:=public.get_chat_unread_state(array['b8670000-0000-0000-0000-000000000001']::uuid[]);
 if(state->>'unread_total')::bigint<>5 or(state#>>'{items,0,unread_count}')::bigint<>3 then raise exception 'Wrong total/subset';end if;
 select sum(s.unread_count)into total from public.get_chat_summaries()s where not s.is_muted;
 if total<>(state->>'unread_total')::bigint then raise exception 'Legacy oracle differs';end if;
 page:=public.get_chat_list_page(null,null,1,'Alpha');
 if jsonb_array_length(page->'items')<>1 or(page->>'unread_total')::bigint<>5 then raise exception 'Search filtered global total';end if;
 begin perform * from private.chat_unread_counts;raise exception 'Counts exposed';exception when insufficient_privilege then null;end;
 begin perform * from private.chat_unread_messages;raise exception 'Evidence exposed';exception when insufficient_privilege then null;end;
 begin perform private.sync_chat_unread_messages(array['c8670000-0000-0000-0000-000000000001']::uuid[],null);raise exception 'Repair exposed';exception when insufficient_privilege then null;end;
 begin perform public.get_chat_unread_state(array_fill('b8670000-0000-0000-0000-000000000001'::uuid,array[51]));raise exception 'Oversized request';exception when sqlstate '22023'then null;end;
 begin perform public.get_chat_unread_state(null);raise exception 'Null request';exception when sqlstate '22023'then null;end;
 begin perform public.get_chat_unread_state(array[null]::uuid[]);raise exception 'Null ID request';exception when sqlstate '22023'then null;end;
 begin perform public.get_chat_unread_state(array[array['b8670000-0000-0000-0000-000000000001'::uuid]]);raise exception 'Multidimensional selection';exception when sqlstate '22023'then null;end;
 begin perform private.get_chat_unread_total_impl();raise exception 'Unmetered total exposed';exception when insufficient_privilege then null;end;
 begin perform private.rebuild_chat_unread_projection(array['b8670000-0000-0000-0000-000000000001']::uuid[]);raise exception 'Backfill exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
insert into public.message_receipts(message_id,user_id,read_at)values('c8670000-0000-0000-0000-000000000001',auth.uid(),now());
select pg_temp.assert_unread_projection();
create temp table unchanged_unread_rows as select conversation_id,user_id,ctid as row_tid from private.chat_unread_counts;
insert into public.message_receipts(message_id,user_id,read_at)values('c8670000-0000-0000-0000-000000000001',auth.uid(),now())on conflict do nothing;
update public.message_receipts set read_at=clock_timestamp() where message_id='c8670000-0000-0000-0000-000000000001';
do $$begin if exists(select 1 from private.chat_unread_counts c join unchanged_unread_rows b using(conversation_id,user_id)where c.ctid<>b.row_tid)then raise exception 'No-op/read timestamp rewrote count';end if;end $$;
delete from public.message_receipts where message_id='c8670000-0000-0000-0000-000000000001';
insert into public.message_receipts(message_id,user_id,read_at)values('c8670000-0000-0000-0000-000000000004',auth.uid(),now());
select pg_temp.assert_unread_projection();
insert into public.message_hidden_for_users(message_id,user_id)values('c8670000-0000-0000-0000-000000000001',auth.uid());
select pg_temp.assert_unread_projection();
with hidden as(insert into public.message_hidden_for_users(message_id,user_id)values('c8670000-0000-0000-0000-000000000002',auth.uid())returning message_id)
insert into public.message_receipts(message_id,user_id,read_at)select message_id,auth.uid(),now()from hidden;
select pg_temp.assert_unread_projection();
with cleared as(delete from public.message_hidden_for_users where message_id='c8670000-0000-0000-0000-000000000002'returning message_id)
delete from public.message_receipts where message_id in(select message_id from cleared);
select pg_temp.assert_unread_projection();
delete from public.message_hidden_for_users where message_id='c8670000-0000-0000-0000-000000000001';
update public.messages set deleted_for_everyone_at=now()where id='c8670000-0000-0000-0000-000000000001';
insert into public.message_receipts(message_id,user_id,read_at)values('c8670000-0000-0000-0000-000000000001',auth.uid(),now());
update public.messages set deleted_for_everyone_at=null where id='c8670000-0000-0000-0000-000000000001';
select pg_temp.assert_unread_projection();
delete from public.message_receipts where message_id='c8670000-0000-0000-0000-000000000001';
update public.conversation_members set cleared_at='2020-01-01 00:00:02+00'where user_id=auth.uid()and conversation_id='b8670000-0000-0000-0000-000000000001';
select pg_temp.assert_unread_projection();
update public.messages set created_at='2021-01-01'where id='c8670000-0000-0000-0000-000000000001';
update public.messages set sender_id=auth.uid()where id='c8670000-0000-0000-0000-000000000003';
select pg_temp.assert_unread_projection();
update public.messages set sender_id='a8670000-0000-0000-0000-000000000002'where id='c8670000-0000-0000-0000-000000000003';
delete from public.messages where id='c8670000-0000-0000-0000-000000000001';
insert into public.message_receipts(message_id,user_id,read_at)values('c8670000-0000-0000-0000-000000000002',auth.uid(),now());
delete from public.messages where id='c8670000-0000-0000-0000-000000000002';
select pg_temp.assert_unread_projection();
update public.conversation_members set cleared_at=null where user_id=auth.uid();
update public.conversation_members set is_muted=true where user_id=auth.uid()and conversation_id='b8670000-0000-0000-0000-000000000002';
update public.conversation_members set hidden_at=now()where user_id=auth.uid()and conversation_id='b8670000-0000-0000-0000-000000000001';
select pg_temp.assert_unread_projection();
set local role authenticated;
do $$begin if(public.get_chat_unread_state()->>'unread_total')::bigint<>0 then raise exception 'Hidden/muted counted in badge';end if;end $$;
reset role;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values('c8670000-0000-0000-0000-000000000008','b8670000-0000-0000-0000-000000000001','a8670000-0000-0000-0000-000000000002','text','restore visible','2030-01-01');
select pg_temp.assert_unread_projection();
delete from public.conversation_members where user_id=auth.uid()and conversation_id='b8670000-0000-0000-0000-000000000001';
select pg_temp.assert_unread_projection();
insert into public.conversation_members(conversation_id,user_id)values('b8670000-0000-0000-0000-000000000001',auth.uid());
select pg_temp.assert_unread_projection();
set local role authenticated;
select public.mark_conversations_read(array['b8670000-0000-0000-0000-000000000001','b8670000-0000-0000-0000-000000000002']::uuid[]);
do $$begin if(public.get_chat_unread_state()->>'unread_total')::bigint<>0 then raise exception 'Bulk read did not clear badge';end if;end $$;
reset role;
select pg_temp.assert_unread_projection();
delete from public.conversations where id::text like'b8670000-%';
select pg_temp.assert_unread_projection();
update private.chat_summary_refresh_quota set request_count=180 where user_id=auth.uid();
set local role authenticated;
do $$begin
 begin perform public.get_chat_unread_state();raise exception 'Empty selection bypassed quota';exception when sqlstate 'PT429'then null;end;
end $$;
reset role;
insert into private.global_account_bans(target_user_id,note)values('a8670000-0000-0000-0000-000000000004','unread guard');
select set_config('request.jwt.claim.sub','a8670000-0000-0000-0000-000000000004',true);
set local role authenticated;
do $$begin
 begin perform public.get_chat_unread_state();raise exception 'Ban bypass';exception when sqlstate 'P0001'then if sqlerrm<>'account_globally_banned'then raise;end if;end;
end $$;
reset role;
insert into private.account_deletion_requests(target_user_id,requested_by,note)values('a8670000-0000-0000-0000-000000000005','admin','unread guard');
select set_config('request.jwt.claim.sub','a8670000-0000-0000-0000-000000000005',true);
set local role authenticated;
do $$begin
 begin perform public.get_chat_unread_state();raise exception 'Pending deletion bypass';exception when sqlstate 'P0001'then if sqlerrm<>'account_pending_deletion'then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$begin begin perform public.get_chat_unread_state();raise exception 'Missing actor accepted';exception when sqlstate '28000'then null;end;end $$;
reset role;
set local role anon;
do $$begin begin perform public.get_chat_unread_state();raise exception 'Anon accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
rollback;
