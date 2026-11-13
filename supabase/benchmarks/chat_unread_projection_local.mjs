// Local rollback-only AB/BA measurement of unread maintenance, not correctness
// with triggers disabled. Normal ledger invariants are checked in SQL tests.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
function sql(source){const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U',process.env.UNREAD_PLAN==='1'?'supabase_admin':'postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:`set statement_timeout='120s';${source}`,encoding:'utf8',timeout:300000,maxBuffer:8*1024*1024});assert.equal(r.status,0,r.stderr||String(r.error));return r;}
const owner='a8680000-0000-0000-0000-000000000001',chat='b8680000-0000-0000-0000-000000000001';
const snapshot=()=>sql("select jsonb_build_object('users',(select count(*)from auth.users),'chats',(select count(*)from public.conversations),'messages',(select count(*)from public.messages),'unread_keys',(select count(*)from private.chat_unread_messages),'unread_counts',(select count(*)from private.chat_unread_counts));").stdout.trim();
const before=snapshot();
const restoreStatistics=()=>sql('vacuum(analyze) public.messages,public.message_receipts,public.profiles,public.conversations,public.conversation_members,private.chat_list_catalog,private.chat_unread_messages,private.chat_unread_counts;');
let source=`begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)select('a8680000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,101)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)select('b8680000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'${owner}',('a8680000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'${owner}' from generate_series(1,100)i;
insert into public.conversation_members(conversation_id,user_id)select id,user_one_id from public.conversations where id::text like'b8680000-%' union all select id,user_two_id from public.conversations where id::text like'b8680000-%';
alter table public.messages disable trigger user;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
select('c8680000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
('b8680000-0000-0000-0000-'||lpad((((i-1)/1000)+1)::text,12,'0'))::uuid,
('a8680000-0000-0000-0000-'||lpad((((i-1)/1000)+2)::text,12,'0'))::uuid,
'text','unread benchmark','2020-01-01'::timestamptz+i*interval'1 second' from generate_series(1,100000)i;
alter table public.messages enable trigger user;
select private.refresh_chat_list_catalog(array(select id from public.conversations where id::text like'b8680000-%'),null);
select private.rebuild_chat_unread_projection(array(select id from public.conversations where id::text like'b8680000-%'));
analyze public.messages;analyze public.message_receipts;analyze public.conversation_members;
analyze private.chat_unread_counts;analyze private.chat_unread_messages;
select set_config('request.jwt.claim.sub','${owner}',true);
`;
const cases={
 send:{op:`insert into public.messages(id,conversation_id,sender_id,type,text)values('d8680000-0000-0000-0000-000000000001','${chat}','${owner}','text','new');`},
 read_1000:{op:`perform public.mark_conversations_read(array['${chat}']::uuid[]);`},
 read_50000:{op:`perform public.mark_conversations_read(array(select id from public.conversations where id::text like'b8680000-%' order by id limit 50));`},
 read_repeat:{setup:`select public.mark_conversations_read(array['${chat}']::uuid[]);`,op:`perform public.mark_conversations_read(array['${chat}']::uuid[]);`},
 hide_1000:{op:`perform public.hide_conversations(array['${chat}']::uuid[],clock_timestamp());`},
 hide_50000:{op:`perform public.hide_conversations(array(select id from public.conversations where id::text like'b8680000-%' order by id limit 50),clock_timestamp());`},
 delete_1000:{op:`update public.messages set deleted_for_everyone_at=clock_timestamp()where conversation_id='${chat}';`},
 purge_tombstones_1000:{setup:`update public.messages set deleted_for_everyone_at=clock_timestamp()-interval'100 days'where conversation_id='${chat}';`,op:`delete from public.messages where conversation_id='${chat}';`},
};
if(process.env.UNREAD_PLAN==='1'){
 const warm=Array.from({length:14},()=>`savepoint warm;select public.mark_conversations_read(array['${chat}']::uuid[]);rollback to warm;`).join('\n');
 let r;try{r=sql(source+warm+`load 'auto_explain';set auto_explain.log_min_duration='50ms';
 set auto_explain.log_nested_statements=on;set auto_explain.log_analyze=on;
 set auto_explain.log_timing=off;set auto_explain.log_buffers=on;set auto_explain.log_level='notice';
 select public.mark_conversations_read(array(select id from public.conversations where id::text like'b8680000-%'order by id limit 50));rollback;`);}finally{restoreStatistics();}
 assert.equal(snapshot(),before);writeFileSync('tmp/chat_unread_nested_plans.log',r.stderr);console.log(r.stdout);process.exit(0);
}
const disable=[['public.messages',['chat_unread_message_insert','chat_unread_message_update','chat_unread_message_delete']],
 ['public.message_receipts',['chat_unread_receipt_insert','chat_unread_receipt_update','chat_unread_receipt_delete']],
 ['public.message_hidden_for_users',['chat_unread_hide_insert','chat_unread_hide_update','chat_unread_hide_delete']],
 ['public.conversation_members',['chat_unread_member_insert','chat_unread_member_update']]]
 .flatMap(([table,names])=>names.map(name=>`alter table ${table} disable trigger ${name};`)).join('\n');
for(const[name,c]of Object.entries(cases))for(let sample=0;sample<7;sample++)for(const variant of(sample%2?['on','off']:['off','on']))source+=`
savepoint trial;
${c.setup??''}
${variant==='off'?disable:''}
create temp table counter_before as select conversation_id,user_id,ctid as row_tid from private.chat_unread_counts;
do $t$declare started timestamptz:=clock_timestamp();elapsed numeric;changed integer;begin
${c.op}
elapsed:=extract(epoch from clock_timestamp()-started)*1000;
select count(*)into changed from private.chat_unread_counts c join counter_before b using(conversation_id,user_id)where c.ctid<>b.row_tid;
raise notice 'UNREAD_COST ${name} ${variant} ${sample} % %',elapsed,changed;end$t$;
rollback to trial;
`;
source+=`select jsonb_build_object('evidence_rows',(select count(*)from private.chat_unread_messages where user_id='${owner}'),
 'evidence_table_bytes',pg_total_relation_size('private.chat_unread_messages'),'count_rows',(select count(*)from private.chat_unread_counts where user_id='${owner}'));
rollback;`;
let r;try{r=sql(source);}finally{restoreStatistics();}
const samples=[...r.stderr.matchAll(/UNREAD_COST (\w+) (\w+) (\d+) ([\d.]+) (\d+)/g)];assert.equal(samples.length,Object.keys(cases).length*14);
const rows=Object.keys(cases).flatMap(name=>['off','on'].map(variant=>{const used=samples.filter(m=>m[1]===name&&m[2]===variant&&+m[3]>=2);const times=used.map(m=>+m[4]).sort((a,b)=>a-b);return{name,variant,median_ms:times[2],max_ms:times.at(-1),max_changed_counter_rows:Math.max(...used.map(m=>+m[5]))};}));
assert.equal(snapshot(),before);const storage=JSON.parse(r.stdout.trim().split(/\r?\n/).at(-1));
const report={rows,storage,fixtures_unchanged:true};writeFileSync('tmp/chat_unread_write_benchmark.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
