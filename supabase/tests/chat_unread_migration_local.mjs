// Replay from the previous schema against populated local data, then roll back.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const migration=readFileSync('supabase/migrations/20261025230324_add_chat_unread_projection.sql','utf8');
const previous=readFileSync('supabase/migrations/20261025220338_add_direct_chat_summary_lookup.sql','utf8');
function definition(source,name){const start=source.indexOf(`create or replace function ${name}`);assert(start>=0);const end=source.indexOf('$$;',source.indexOf('as $$',start));assert(end>=0);return source.slice(start,end+3);}
const sql=`begin;set local statement_timeout='120s';
${definition(previous,'private.get_chat_summaries_by_ids_impl')}
drop function public.get_chat_unread_state(uuid[]);
drop function private.get_chat_unread_state_impl(uuid[]);
drop function private.get_chat_list_page_impl(timestamptz,uuid,integer,text);
alter function private.get_chat_list_page_without_unread_impl(timestamptz,uuid,integer,text)rename to get_chat_list_page_impl;
grant execute on function private.get_chat_list_page_impl(timestamptz,uuid,integer,text)to authenticated,service_role;
drop function private.get_chat_unread_total_impl();
drop function private.chat_unread_members_changed()cascade;
drop function private.chat_unread_messages_changed()cascade;
drop function private.chat_unread_receipts_changed()cascade;
drop function private.chat_unread_hides_changed()cascade;
drop function private.sync_chat_unread_messages(uuid[],uuid[]);
drop function private.sync_chat_unread_messages_impl(uuid[],uuid[],text);
drop function private.rebuild_chat_unread_projection(uuid[]);
drop table private.chat_unread_messages;
drop table private.chat_unread_counts;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select('a8690000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'from generate_series(1,5)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select('b8690000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'a8690000-0000-0000-0000-000000000001',('a8690000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'a8690000-0000-0000-0000-000000000001'from generate_series(1,4)i;
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like'b8690000-%'
union all select id,user_two_id from public.conversations where id::text like'b8690000-%';
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select('c8690000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
('b8690000-0000-0000-0000-'||lpad((((i-1)/100)+1)::text,12,'0'))::uuid,
('a8690000-0000-0000-0000-'||lpad((((i-1)/100)+2)::text,12,'0'))::uuid,
'text','populated migration','2020-01-01'::timestamptz+i*interval'1 second'from generate_series(1,400)i;
insert into public.message_receipts(message_id,user_id,read_at)
select id,'a8690000-0000-0000-0000-000000000001',now()from public.messages where id::text like'c8690000-%'and right(id::text,2)::integer%3=0;
insert into public.message_hidden_for_users(message_id,user_id)
select id,'a8690000-0000-0000-0000-000000000001'from public.messages where id::text like'c8690000-%'and right(id::text,2)::integer%7=0;
update public.messages set deleted_for_everyone_at=now()where id::text like'c8690000-%'and right(id::text,2)::integer%11=0;
update public.conversation_members set is_muted=true where conversation_id='b8690000-0000-0000-0000-000000000002'and user_id='a8690000-0000-0000-0000-000000000001';
update public.conversation_members set hidden_at=now(),cleared_at='2020-01-01 00:04:00+00'where conversation_id='b8690000-0000-0000-0000-000000000003'and user_id='a8690000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','a8690000-0000-0000-0000-000000000001',true);
create temp table summaries_before as select jsonb_agg(to_jsonb(s)order by id)value from public.get_chat_summaries()s;
create temp table unread_before as select coalesce(sum(unread_count)filter(where not is_muted),0)::bigint total from public.get_chat_summaries();
${migration}
do $$declare expected jsonb;actual jsonb;begin
 select value into expected from summaries_before;
 select jsonb_agg(to_jsonb(s)order by id)into actual from public.get_chat_summaries_by_ids(array(select id from public.conversations where id::text like'b8690000-%'))s;
 if actual is distinct from expected then raise exception 'Existing summaries changed after backfill';end if;
 if(public.get_chat_unread_state()->>'unread_total')::bigint<>(select total from unread_before)then raise exception 'Backfill changed whole-account total';end if;
 if(public.get_chat_list_page(null,null,1,'')->>'unread_total')::bigint<>(select total from unread_before)then raise exception 'Page wrapper lost backfilled total';end if;
 if has_function_privilege('anon','public.get_chat_unread_state(uuid[])','execute')
 or has_function_privilege('authenticated','private.rebuild_chat_unread_projection(uuid[])','execute')
 or has_function_privilege('authenticated','private.get_chat_unread_total_impl()','execute')
 or has_table_privilege('authenticated','private.chat_unread_messages','select')
 or not has_function_privilege('authenticated','public.get_chat_unread_state(uuid[])','execute')then raise exception 'Migration ACL changed';end if;
end $$;
insert into public.messages(id,conversation_id,sender_id,type,text)values('d8690000-0000-0000-0000-000000000001','b8690000-0000-0000-0000-000000000001','a8690000-0000-0000-0000-000000000002','text','post migration');
do $$begin if(public.get_chat_unread_state()->>'unread_total')::bigint<>(select total+1 from unread_before)then raise exception 'Triggers not active after migration';end if;end $$;
rollback;`;
const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:sql,encoding:'utf8',timeout:150000,maxBuffer:4*1024*1024});
writeFileSync('tmp/chat_unread_migration.log',(r.stdout??'')+'\n'+(r.stderr??''));
assert.equal(r.status,0,r.stderr||String(r.error));
const report={passed:true,populated_backfill:true,existing_summaries_preserved:true,hidden_muted_read_deleted:true,privileges_checked:true,post_migration_insert:true,rollback:true};
writeFileSync('tmp/chat_unread_migration.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
