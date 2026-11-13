// Before/after cost of maintaining the catalog. All fixture data rolls back.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const phase=process.env.CHAT_CATALOG_PHASE??'before';
assert(['before','after','paired'].includes(phase));
function sql(query){const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:`set statement_timeout='120s';\n${query}`,encoding:'utf8',timeout:150000,maxBuffer:4*1024*1024});assert.equal(r.status,0,r.stderr||String(r.error));return r;}
const owner='a8610000-0000-0000-0000-000000000001';
const chat='b8610000-0000-0000-0000-000000000001';
const snapshot=()=>sql("select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'receipts',(select count(*) from public.message_receipts));").stdout.trim();
const before=snapshot();
const catalogExists=sql("select to_regclass('private.chat_list_catalog') is not null;").stdout.trim()==='t';
assert(phase==='before'?!catalogExists:catalogExists,'Use before only before applying the migration; use paired afterwards');
let source=`begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) select ('a8610000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,101) i;
insert into public.conversations(id,user_one_id,user_two_id,created_by) select ('b8610000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'${owner}',('a8610000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'${owner}' from generate_series(1,100) i;
insert into public.conversation_members(conversation_id,user_id) select id,user_one_id from public.conversations where id::text like 'b8610000-%' union all select id,user_two_id from public.conversations where id::text like 'b8610000-%';
alter table public.messages disable trigger user;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at) select ('c8610000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,('b8610000-0000-0000-0000-'||lpad((((i-1)/1000)+1)::text,12,'0'))::uuid,('a8610000-0000-0000-0000-'||lpad((((i-1)/1000)+2)::text,12,'0'))::uuid,'text','fixture','2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,100000) i;
alter table public.messages enable trigger user;
analyze public.messages;analyze public.conversation_members;analyze public.message_receipts;
select set_config('request.jwt.claim.sub','${owner}',true);
`;
if(phase!=='before')source+=`select private.refresh_chat_list_catalog(array(select id from public.conversations where id::text like 'b8610000-%'),null);`;
source+=`do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
perform private.rebuild_chat_unread_projection(array(select id from public.conversations where id::text like 'b8610000-%'));end if;end $f$;`;
const cases={
send:`insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values('d8610000-0000-0000-0000-000000000001','${chat}','${owner}','text','new message',clock_timestamp());`,
hide:`perform public.hide_conversations(array['${chat}']::uuid[],clock_timestamp());`,
delete_1000:`update public.messages set deleted_for_everyone_at=clock_timestamp() where conversation_id='${chat}';`,
read_1000:`perform public.mark_conversations_read(array['${chat}']::uuid[]);`,
read_50000:`perform public.mark_conversations_read(array(select id from public.conversations where id::text like 'b8610000-%' order by id limit 50));`,
};
const disableCatalog=`
alter table public.messages disable trigger chat_list_messages_insert;
alter table public.messages disable trigger chat_list_messages_update;
alter table public.messages disable trigger chat_list_messages_delete;
alter table public.conversation_members disable trigger chat_list_member_insert;
alter table public.conversation_members disable trigger chat_list_member_visibility;
alter table public.message_hidden_for_users disable trigger chat_list_hidden_insert;
alter table public.message_hidden_for_users disable trigger chat_list_hidden_update;
alter table public.message_hidden_for_users disable trigger chat_list_hidden_delete;`;
for(const [name,operation]of Object.entries(cases))for(let i=0;i<9;i++)for(const variant of (phase==='paired'?(i%2?['on','off']:['off','on']):[phase]))source+=`
savepoint trial;
${variant==='off'?disableCatalog:''}
do $t$ declare started timestamptz:=clock_timestamp();begin ${operation}
raise notice 'CAT_WRITE ${name} ${variant} ${i} %',extract(epoch from clock_timestamp()-started)*1000;end $t$;
rollback to trial;
`;
source+='rollback;';let r;
try {r=sql(source);} finally {
 // ANALYZE and aborted tuples survive rollback; do not poison later SDK plans.
 sql('vacuum(analyze) public.messages,public.message_receipts,public.profiles,public.conversations,public.conversation_members'+(catalogExists?',private.chat_list_catalog':'')+';');
}
const samples=[...r.stderr.matchAll(/CAT_WRITE (\w+) (\w+) (\d+) ([\d.]+)/g)];assert.equal(samples.length,Object.keys(cases).length*9*(phase==='paired'?2:1));
const rows=Object.keys(cases).flatMap(name=>(phase==='paired'?['off','on']:[phase]).map(variant=>{const times=samples.filter(m=>m[1]===name&&m[2]===variant&&+m[3]>=2).map(m=>+m[4]).sort((a,b)=>a-b);return{name,variant,median_ms:times[3]};}));
assert.equal(snapshot(),before);const report={phase,rows,fixtures_unchanged:true};
writeFileSync(`tmp/chat_catalog_write_${phase}.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report));
