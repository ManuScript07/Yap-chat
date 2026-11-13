// Compact-size estimate, without dead tuples from repeated AB/BA rollbacks.
// TEMP copies have the real columns and indexes, but no application triggers.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const source=`begin;set local statement_timeout='30s';
create temp table unread_storage_sample(like private.chat_unread_messages including all);
create temp table unread_count_sample(like private.chat_unread_counts including all);
insert into unread_count_sample(conversation_id,user_id,is_visible,is_muted,unread_count)
select md5('unread-chat:'||i)::uuid,'a8680000-0000-0000-0000-000000000001',true,false,1000 from generate_series(1,100)i;
insert into unread_storage_sample(message_id,user_id,conversation_id,created_at)
select md5('unread-message:'||i)::uuid,'a8680000-0000-0000-0000-000000000001',md5('unread-chat:'||(((i-1)/1000)+1))::uuid,'2020-01-01'::timestamptz+i*interval'1 second'from generate_series(1,100000)i;
select jsonb_build_object('evidence_rows',100000,'evidence_with_indexes_bytes',pg_total_relation_size('pg_temp.unread_storage_sample'),
 'evidence_mean_tuple_bytes',(select avg(pg_column_size(s))from unread_storage_sample s),
 'count_rows',100,'counts_with_indexes_bytes',pg_total_relation_size('pg_temp.unread_count_sample'));
rollback;`;
const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:source,encoding:'utf8',timeout:40000});
assert.equal(r.status,0,r.stderr||String(r.error));const report={...JSON.parse(r.stdout.trim()),rollback:true};
writeFileSync('tmp/chat_unread_storage.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
