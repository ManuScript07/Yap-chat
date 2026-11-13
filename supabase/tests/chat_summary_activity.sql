-- Raw summary time is the exact catalogue order, before any local preview merge.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8770000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'
from generate_series(1,5)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values
('b8770000-0000-0000-0000-000000000001','a8770000-0000-0000-0000-000000000001','a8770000-0000-0000-0000-000000000002','a8770000-0000-0000-0000-000000000001','2020-01-01 00:00:00.123456+00'),
('b8770000-0000-0000-0000-000000000002','a8770000-0000-0000-0000-000000000001','a8770000-0000-0000-0000-000000000003','a8770000-0000-0000-0000-000000000001','2020-01-01 00:00:00.654321+00'),
('b8770000-0000-0000-0000-000000000003','a8770000-0000-0000-0000-000000000004','a8770000-0000-0000-0000-000000000005','a8770000-0000-0000-0000-000000000004','2020-01-01');
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8770000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8770000-%';

create function pg_temp.assert_summary_activity(actor uuid) returns void
language plpgsql set search_path='' as $$
declare payload jsonb; page jsonb; direct jsonb; item jsonb; catalogue timestamptz;
        requested uuid[]; expected uuid[]; actual uuid[]; peer uuid;
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select array_agg(id order by id)into requested from public.conversations where id::text like'b8770000-%';
 payload:=public.get_chat_unread_state(requested);
 select array_agg(cm.conversation_id order by cm.conversation_id)into expected
 from public.conversation_members cm where cm.user_id=actor and cm.hidden_at is null and cm.conversation_id=any(requested);
 select array_agg((x->>'id')::uuid order by (x->>'id')::uuid)into actual from jsonb_array_elements(payload->'items')x;
 if actual is distinct from expected then raise exception 'Summary visibility differs';end if;
 page:=public.get_chat_list_page(page_size=>50);
 for item in select x from jsonb_array_elements(payload->'items')x loop
   select c.activity_at into strict catalogue from private.chat_list_catalog c
   where c.user_id=actor and c.conversation_id=(item->>'id')::uuid;
   if (item->>'last_message_at')::timestamptz is distinct from catalogue then
     raise exception 'Raw summary lost catalogue activity: %',item;
   end if;
   if not exists(select 1 from jsonb_array_elements(page->'items')p
      where p->>'id'=item->>'id' and (p->>'list_activity_at')::timestamptz=catalogue) then
     raise exception 'Page and addressed order differ';
   end if;
   select case when c.user_one_id=actor then c.user_two_id else c.user_one_id end
   into strict peer from public.conversations c where c.id=(item->>'id')::uuid;
   direct:=public.get_direct_chat_summary(peer);
   if jsonb_array_length(direct)<>1 or (direct->0->>'last_message_at')::timestamptz is distinct from catalogue then
     raise exception 'Peer lookup activity differs';
   end if;
 end loop;
end;$$;

select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values
('c8770000-0000-0000-0000-000000000001','b8770000-0000-0000-0000-000000000001','a8770000-0000-0000-0000-000000000002','text','older','2026-01-01 00:00:00.123456+00'),
('c8770000-0000-0000-0000-000000000002','b8770000-0000-0000-0000-000000000001','a8770000-0000-0000-0000-000000000001','text','latest','2026-01-01 00:00:00.123457+00');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000002');
insert into public.message_hidden_for_users(message_id,user_id)values
('c8770000-0000-0000-0000-000000000002','a8770000-0000-0000-0000-000000000001');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000002');
update public.messages set deleted_for_everyone_at=clock_timestamp()where id='c8770000-0000-0000-0000-000000000001';
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
update public.conversation_members set cleared_at='2026-01-01 00:00:00.123457+00'
where conversation_id='b8770000-0000-0000-0000-000000000001'and user_id='a8770000-0000-0000-0000-000000000002';
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000002');
update public.conversation_members set hidden_at=clock_timestamp()
where conversation_id='b8770000-0000-0000-0000-000000000002'and user_id='a8770000-0000-0000-0000-000000000001';
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values
('c8770000-0000-0000-0000-000000000003','b8770000-0000-0000-0000-000000000002','a8770000-0000-0000-0000-000000000003','text','restore','2026-01-02 00:00:00.999999+00');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
update public.conversation_members set is_muted=true where user_id='a8770000-0000-0000-0000-000000000001';
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
delete from public.messages where id='c8770000-0000-0000-0000-000000000002';
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000001');
select pg_temp.assert_summary_activity('a8770000-0000-0000-0000-000000000004');

-- Calling the actual public endpoint with the app role still excludes foreign
-- chat IDs and does not expose the private order table.
select set_config('request.jwt.claim.sub','a8770000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$begin
 if jsonb_array_length(public.get_chat_unread_state(array['b8770000-0000-0000-0000-000000000003']::uuid[])->'items')<>0 then
   raise exception 'Foreign chat exposed';
 end if;
 begin perform 1 from private.chat_list_catalog;raise exception 'Private order exposed';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
