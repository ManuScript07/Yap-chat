// Replay the migration from the previous function definition, local rollback only.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const old=readFileSync('supabase/migrations/20261025183743_add_targeted_chat_summary_refresh.sql','utf8').replaceAll('\r\n','\n');
const next=readFileSync('supabase/migrations/20261025220338_add_direct_chat_summary_lookup.sql','utf8').replaceAll('\r\n','\n');
function summaryDefinition(source){const start=source.indexOf('create or replace function private.get_chat_summaries_by_ids_impl');assert(start>=0);const end=source.indexOf('$$;',source.indexOf('as $$',start));assert(end>=0);return source.slice(start,end+3);}
const previous=summaryDefinition(old),current=summaryDefinition(next);
assert.equal(current.slice(current.indexOf('  return query')),previous.slice(previous.indexOf('  return query')),'The enrichment SELECT must remain unchanged');
const sql=`begin;
${previous}
drop function public.get_direct_chat_summary(uuid);
drop function private.get_direct_chat_summary_impl(uuid);
drop function private.consume_chat_summary_refresh_quota(integer);
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)values
('a8660000-0000-0000-0000-000000000001',false,false,'{}'),('a8660000-0000-0000-0000-000000000002',false,false,'{}');
insert into public.conversations(id,user_one_id,user_two_id,created_by)values
('b8660000-0000-0000-0000-000000000001','a8660000-0000-0000-0000-000000000001','a8660000-0000-0000-0000-000000000002','a8660000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id)values
('b8660000-0000-0000-0000-000000000001','a8660000-0000-0000-0000-000000000001'),('b8660000-0000-0000-0000-000000000001','a8660000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','a8660000-0000-0000-0000-000000000001',true);
create temp table expected_summary as select jsonb_agg(to_jsonb(s)) as value from public.get_chat_summaries_by_ids(array['b8660000-0000-0000-0000-000000000001']::uuid[])s;
${next}
do $$declare result jsonb;begin
 result:=public.get_direct_chat_summary('a8660000-0000-0000-0000-000000000002');
 if result is distinct from(select value from expected_summary)then raise exception 'Migration changed existing summary';end if;
 if has_function_privilege('anon','public.get_direct_chat_summary(uuid)','execute')
 or has_function_privilege('authenticated','private.consume_chat_summary_refresh_quota(integer)','execute')
 or not has_function_privilege('authenticated','public.get_direct_chat_summary(uuid)','execute')
 then raise exception 'Incorrect migration privileges';end if;
 if(select request_count from private.chat_summary_refresh_quota where user_id=auth.uid())<>2 then raise exception 'Migration reset or double-charged quota';end if;
end $$;
rollback;`;
const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:sql,encoding:'utf8',timeout:30000});
writeFileSync('tmp/direct_chat_lookup_migration.log',(r.stdout??'')+'\n'+(r.stderr??''));
assert.equal(r.status,0,r.stderr||String(r.error));
const report={passed:true,enrichment_select_unchanged:true,existing_summary_preserved:true,quota_preserved:true,privileges_checked:true,rollback:true};
writeFileSync('tmp/direct_chat_lookup_migration.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
