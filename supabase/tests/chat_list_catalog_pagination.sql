begin;
create function pg_temp.assert_chat_catalog()
returns void language plpgsql set search_path='' as $$
declare mismatch integer;
begin
  with expected as (
    select member.user_id,member.conversation_id,coalesce(latest.created_at,c.created_at) as activity_at,
      latest.id as latest_message_id,member.hidden_at is null as is_visible
    from public.conversation_members member join public.conversations c on c.id=member.conversation_id
    left join lateral (
      select message.id,message.created_at from public.messages message
      where member.hidden_at is null and message.conversation_id=member.conversation_id
        and message.deleted_for_everyone_at is null
        and message.created_at>coalesce(member.cleared_at,'-infinity'::timestamptz)
        and not exists(select 1 from public.message_hidden_for_users h where h.message_id=message.id and h.user_id=member.user_id)
      order by message.created_at desc,message.id desc limit 1
    ) latest on true
  ), differences as (
    (select * from expected except select user_id,conversation_id,activity_at,latest_message_id,is_visible from private.chat_list_catalog)
    union all
    (select user_id,conversation_id,activity_at,latest_message_id,is_visible from private.chat_list_catalog except select * from expected)
  ) select count(*) into mismatch from differences;
  if mismatch<>0 then raise exception 'Catalog differs from visibility rules: % rows',mismatch;end if;
end; $$;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8620000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,56) i;
update public.profiles set display_name=case id::text
 when 'a8620000-0000-0000-0000-000000000002' then 'Алёна'
 when 'a8620000-0000-0000-0000-000000000003' then 'алексей'
 when 'a8620000-0000-0000-0000-000000000004' then 'XАлёна'
 when 'a8620000-0000-0000-0000-000000000005' then '100% user'
 when 'a8620000-0000-0000-0000-000000000006' then 'under_score'
 when 'a8620000-0000-0000-0000-000000000008' then 'Hidden ban'
 when 'a8620000-0000-0000-0000-000000000009' then 'Hidden deletion'
 else 'Other '||id::text end where id::text like 'a8620000-%';
insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at)
select ('b8620000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'a8620000-0000-0000-0000-000000000001',
 ('a8620000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'a8620000-0000-0000-0000-000000000001',
 '2020-01-01 12:34:56.123456+00' from generate_series(1,53) i;
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8620000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8620000-%';
select pg_temp.assert_chat_catalog();
select set_config('request.jwt.claim.sub','a8620000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ declare first_page jsonb; second_page jsonb; cursor jsonb; combined uuid[];begin
 first_page:=public.get_chat_list_page();cursor:=first_page->'next_cursor';
 if jsonb_array_length(first_page->'items')<>50 or first_page->>'has_more'<>'true' then raise exception 'First page invalid';end if;
 second_page:=public.get_chat_list_page((cursor->>'activity_at')::timestamptz,(cursor->>'conversation_id')::uuid,50,'');
 if jsonb_array_length(second_page->'items')<>3 or second_page->>'has_more'<>'false' or second_page->'next_cursor'<>'null'::jsonb then raise exception 'Last page invalid';end if;
 select array_agg((item->>'id')::uuid) into combined from jsonb_array_elements((first_page->'items')||(second_page->'items')) item;
 if cardinality(combined)<>53 or (select count(distinct x) from unnest(combined) x)<>53 then raise exception 'Tie cursor skipped/duplicated rows';end if;
 if cursor->>'activity_at' not like '2020-01-01T12:34:56.123456%' then raise exception 'Cursor lost microseconds';end if;
 if exists(select 1 from jsonb_array_elements(first_page->'items') item
   left join public.get_chat_summaries() legacy on legacy.id=(item->>'id')::uuid
   where (item-'list_activity_at') is distinct from to_jsonb(legacy)) then raise exception 'Metadata contract mismatch';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'  АЛ ')->'items')<>2 then raise exception 'Prefix normalization failed';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'лё')->'items')<>0 then raise exception 'Search became substring';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'100%')->'items')<>1 then raise exception 'Literal percent failed';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'under_')->'items')<>1 then raise exception 'Literal underscore failed';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,''' OR true --')->'items')<>0 then raise exception 'Search SQL injection';end if;
 begin perform public.get_chat_list_page(null,null,51,'');raise exception '51 accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_chat_list_page(null,null,0,'');raise exception '0 accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_chat_list_page(null,null,null,'');raise exception 'null size accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_chat_list_page(null,'b8620000-0000-0000-0000-000000000001',1,'');raise exception 'Half cursor accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_chat_list_page('infinity','b8620000-0000-0000-0000-000000000001',1,'');raise exception 'Infinite cursor accepted';exception when sqlstate '22023' then null;end;
 begin perform public.get_chat_list_page(null,null,1,repeat('a',101));raise exception 'Oversized query accepted';exception when sqlstate '22023' then null;end;
end $$;
reset role;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values
 ('c8620000-0000-0000-0000-000000000001','b8620000-0000-0000-0000-000000000001','a8620000-0000-0000-0000-000000000002','text','old','2021-01-01'),
 ('c8620000-0000-0000-0000-000000000002','b8620000-0000-0000-0000-000000000001','a8620000-0000-0000-0000-000000000001','image','','2022-01-01'),
 ('c8620000-0000-0000-0000-000000000003','b8620000-0000-0000-0000-000000000002','a8620000-0000-0000-0000-000000000003','audio','','2023-01-01');
select pg_temp.assert_chat_catalog();
insert into public.message_hidden_for_users(message_id,user_id) values('c8620000-0000-0000-0000-000000000002','a8620000-0000-0000-0000-000000000001');
select pg_temp.assert_chat_catalog();
update public.message_hidden_for_users set user_id='a8620000-0000-0000-0000-000000000002' where message_id='c8620000-0000-0000-0000-000000000002';
select pg_temp.assert_chat_catalog();
delete from public.message_hidden_for_users where message_id='c8620000-0000-0000-0000-000000000002';
select pg_temp.assert_chat_catalog();
update public.messages set deleted_for_everyone_at=now() where id='c8620000-0000-0000-0000-000000000002';
select pg_temp.assert_chat_catalog();
update public.messages set deleted_for_everyone_at=null where id='c8620000-0000-0000-0000-000000000002';
select pg_temp.assert_chat_catalog();
update public.messages set created_at='2024-01-01' where id='c8620000-0000-0000-0000-000000000001';
select pg_temp.assert_chat_catalog();
update public.conversation_members set cleared_at='2025-01-01',hidden_at=now() where user_id='a8620000-0000-0000-0000-000000000001' and conversation_id='b8620000-0000-0000-0000-000000000001';
select pg_temp.assert_chat_catalog();
insert into public.messages(id,conversation_id,sender_id,type,text) values('c8620000-0000-0000-0000-000000000004','b8620000-0000-0000-0000-000000000001','a8620000-0000-0000-0000-000000000002','text','restores hidden');
select pg_temp.assert_chat_catalog();
delete from public.messages where id='c8620000-0000-0000-0000-000000000004';
select pg_temp.assert_chat_catalog();
create temp table catalog_tuples_before as select user_id,conversation_id,ctid as row_tid from private.chat_list_catalog;
set local role authenticated;
select public.mark_conversations_read(array['b8620000-0000-0000-0000-000000000002']::uuid[]);
select public.set_conversations_muted(array['b8620000-0000-0000-0000-000000000002']::uuid[],true);
reset role;
do $$ begin
 if exists(select 1 from private.chat_list_catalog c join catalog_tuples_before b using(user_id,conversation_id) where c.ctid<>b.row_tid) then raise exception 'Read/mute rewrote activity catalog';end if;
end $$;
insert into private.global_account_bans(target_user_id,note) values('a8620000-0000-0000-0000-000000000008','search test');
insert into private.account_deletion_requests(target_user_id,requested_by,note) values('a8620000-0000-0000-0000-000000000009','admin','search test');
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'Hidden')->'items')<>0 then raise exception 'Search exposed redacted names';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'Заблок')->'items')<>1 then raise exception 'Ban alias missing';end if;
 if jsonb_array_length(public.get_chat_list_page(null,null,50,'Удалён')->'items')<>1 then raise exception 'Deleted alias missing';end if;
end $$;
reset role;
update public.profiles set display_name='Changed live' where id='a8620000-0000-0000-0000-000000000003';
set local role authenticated;
do $$ begin if jsonb_array_length(public.get_chat_list_page(null,null,50,'Changed')->'items')<>1 then raise exception 'Rename not searched';end if;end $$;
reset role;
delete from public.conversation_members where user_id='a8620000-0000-0000-0000-000000000001' and conversation_id='b8620000-0000-0000-0000-000000000053';
select pg_temp.assert_chat_catalog();
delete from public.conversations where id='b8620000-0000-0000-0000-000000000001';
select pg_temp.assert_chat_catalog();
select set_config('request.jwt.claim.sub','a8620000-0000-0000-0000-000000000056',true);
set local role authenticated;
do $$ begin
 if public.get_chat_list_page()->'items'<>'[]'::jsonb then raise exception 'Non-member exposed';end if;
 begin perform * from private.chat_list_catalog;raise exception 'Catalog readable';exception when insufficient_privilege then null;end;
 begin perform private.refresh_chat_list_catalog(array['b8620000-0000-0000-0000-000000000002']::uuid[],null);raise exception 'Client repair allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update private.chat_list_page_quota set request_count=120 where user_id=auth.uid();
set local role authenticated;
do $$ begin begin perform public.get_chat_list_page();raise exception 'Page quota bypass';exception when sqlstate 'PT429' then null;end;end $$;
reset role;
update private.chat_list_page_quota set window_started_at=statement_timestamp()-interval '61 seconds' where user_id=auth.uid();
set local role authenticated;
select public.get_chat_list_page();
reset role;
insert into private.global_account_bans(target_user_id,note) values('a8620000-0000-0000-0000-000000000054','page actor guard');
select set_config('request.jwt.claim.sub','a8620000-0000-0000-0000-000000000054',true);
set local role authenticated;
do $$ begin
 begin perform public.get_chat_list_page();raise exception 'Banned actor accepted';exception when sqlstate 'P0001' then if sqlerrm<>'account_globally_banned' then raise;end if;end;
end $$;
reset role;
insert into private.account_deletion_requests(target_user_id,requested_by,note) values('a8620000-0000-0000-0000-000000000055','admin','page actor guard');
select set_config('request.jwt.claim.sub','a8620000-0000-0000-0000-000000000055',true);
set local role authenticated;
do $$ begin
 begin perform public.get_chat_list_page();raise exception 'Pending actor accepted';exception when sqlstate 'P0001' then if sqlerrm<>'account_pending_deletion' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin begin perform public.get_chat_list_page();raise exception 'Missing auth accepted';exception when sqlstate '28000' then null;end;end $$;
reset role;
set local role anon;
do $$ begin begin perform public.get_chat_list_page();raise exception 'Anon accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
rollback;
