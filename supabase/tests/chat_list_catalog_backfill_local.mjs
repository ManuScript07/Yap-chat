// Recreate the new migration in a rollback-only LOCAL transaction, over data.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
const migration=readFileSync('supabase/migrations/20261025210630_add_chat_list_catalog_pagination.sql','utf8');
const sql=`begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8640000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,21)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('b8640000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'a8640000-0000-0000-0000-000000000001',('a8640000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'a8640000-0000-0000-0000-000000000001' from generate_series(1,20)i;
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8640000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8640000-%';
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select ('c8640000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,('b8640000-0000-0000-0000-'||lpad((((i-1)/100)+1)::text,12,'0'))::uuid,
('a8640000-0000-0000-0000-'||lpad((((i-1)/100)+2)::text,12,'0'))::uuid,'text','backfill fixture','2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,2000)i;
update public.messages set deleted_for_everyone_at=now() where id in('c8640000-0000-0000-0000-000000000100','c8640000-0000-0000-0000-000000000200');
insert into public.message_hidden_for_users(message_id,user_id)values('c8640000-0000-0000-0000-000000000300','a8640000-0000-0000-0000-000000000001');
update public.conversation_members set hidden_at=now() where conversation_id='b8640000-0000-0000-0000-000000000004';
update public.conversation_members set cleared_at='2021-01-01' where conversation_id='b8640000-0000-0000-0000-000000000005';
create temp table expected_chat_catalog as select * from private.chat_list_catalog;
drop function public.get_chat_list_page(timestamptz,uuid,integer,text);
drop function private.get_chat_list_page_impl(timestamptz,uuid,integer,text);
drop function private.chat_list_member_changed(),private.chat_list_messages_inserted(),private.chat_list_messages_updated(),private.chat_list_messages_deleted(),private.chat_list_hidden_changed() cascade;
drop table private.chat_list_catalog,private.chat_list_page_quota;
${migration}
do $$begin
 if exists((select * from expected_chat_catalog except select * from private.chat_list_catalog)
 union all(select * from private.chat_list_catalog except select * from expected_chat_catalog))then raise exception 'Migration backfill differs from live triggers';end if;
 if(select count(*)from private.chat_list_catalog where conversation_id::text like 'b8640000-%')<>40 then raise exception 'Backfill lost memberships';end if;
end $$;
rollback;`;
const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:sql,encoding:'utf8',timeout:150000,maxBuffer:1024*1024});
writeFileSync('tmp/chat_list_catalog_backfill.log',(r.stdout??'')+'\n'+(r.stderr??''));
assert.equal(r.status,0,r.stderr||String(r.error));console.log(JSON.stringify({passed:true,backfill_fixture_chats:20,messages:2000,existing_catalog_preserved:true,rollback:true}));
