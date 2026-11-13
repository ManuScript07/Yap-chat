// Local Docker only. Identical bounded pages at 1,000 and 10,000 conversations.
// Fixtures and trigger changes roll back; no production endpoint is accessed.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
function sql(query) {
 const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:query,encoding:'utf8',timeout:240000,maxBuffer:4*1024*1024});
 assert.equal(r.status,0,r.stderr||String(r.error));return r;
}
const snapshot=()=>sql("select jsonb_build_object('users',(select count(*) from auth.users),'conversations',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'catalog',(select count(*) from private.chat_list_catalog));").stdout.trim();
const before=snapshot(),rows=[];
const owner='a8630000-0000-0000-0000-000000000001';
try { for(const count of [1000,10000]) {
 sql('vacuum(analyze) private.chat_list_catalog;');
 let source=`begin;set local statement_timeout='120s';
 insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
 select ('a8630000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,${count+1}) i;
 insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at)
 select ('b8630000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'${owner}',('a8630000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'${owner}','2019-01-01' from generate_series(1,${count}) i;
 alter table public.conversation_members disable trigger chat_list_member_insert;
 insert into public.conversation_members(conversation_id,user_id)
 select id,user_one_id from public.conversations where id::text like 'b8630000-%'
 union all select id,user_two_id from public.conversations where id::text like 'b8630000-%';
 alter table public.conversation_members enable trigger chat_list_member_insert;
 alter table public.messages disable trigger user;
 insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
 select ('c8630000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('b8630000-0000-0000-0000-'||lpad((((i-1)/100)+1)::text,12,'0'))::uuid,
 ('a8630000-0000-0000-0000-'||lpad((((i-1)/100)+2)::text,12,'0'))::uuid,
 'text','benchmark','2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,${count*100}) i;
 alter table public.messages enable trigger user;
 update public.profiles set display_name='Scale '||id::text where id::text like 'a8630000-%';
 update public.profiles set display_name='Rare target' where id='a8630000-0000-0000-0000-${String(count+1).padStart(12,'0')}';
 select private.refresh_chat_list_catalog(array(select id from public.conversations where id::text like 'b8630000-%'),null);
 do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
 perform private.rebuild_chat_unread_projection(array(select id from public.conversations where id::text like 'b8630000-%'));end if;end $f$;
 analyze private.chat_list_catalog;analyze public.messages;analyze public.profiles;analyze public.conversation_members;
 analyze private.chat_unread_counts;analyze private.chat_unread_messages;
 select set_config('request.jwt.claim.sub','${owner}',true);
 `;
 const half=Math.floor(count/2),tail=count-51;
 const cursor=offset=>`'2020-01-01'::timestamptz+${(count-offset)*100}*interval '1 second','b8630000-0000-0000-0000-${String(count-offset).padStart(12,'0')}'::uuid`;
 const cases={head:`null,null,50,''`,middle:`${cursor(half)},50,''`,tail:`${cursor(tail)},50,''`,prefix:`null,null,50,'Scale'`,rare:`null,null,50,'Rare'`,missing:`null,null,50,'Absent'`,alias:`null,null,50,'Удалён'`};
 for(const[name,args]of Object.entries(cases)) for(let sample=0;sample<7;sample++)source+=`
 do $t$ declare started timestamptz:=clock_timestamp();result jsonb;begin
 result:=public.get_chat_list_page(${args});
 if jsonb_array_length(result->'items')>50 then raise exception 'unbounded page';end if;
 raise notice 'PAGE_BENCH ${name} ${sample} %',extract(epoch from clock_timestamp()-started)*1000;end $t$;
 `;
 for(let sample=0;sample<7;sample++)source+=`
 do $t$ declare started timestamptz:=clock_timestamp();result jsonb;begin
 result:=public.get_direct_chat_summary('a8630000-0000-0000-0000-${String(half+1).padStart(12,'0')}');
 if jsonb_array_length(result)<>1 then raise exception 'Addressed lookup lost member';end if;
 raise notice 'PAGE_BENCH direct_peer ${sample} %',extract(epoch from clock_timestamp()-started)*1000;end $t$;
 `;
 for(let sample=0;sample<7;sample++)source+=`
 do $t$ declare started timestamptz:=clock_timestamp();result jsonb;begin
 result:=public.get_chat_unread_state();
 if(result->>'unread_total')::bigint<>${count*100} then raise exception 'Global unread total differs';end if;
 raise notice 'PAGE_BENCH unread_total ${sample} %',extract(epoch from clock_timestamp()-started)*1000;end $t$;
 `;
 for(let sample=0;sample<7;sample++)source+=`
 do $t$ declare started timestamptz:=clock_timestamp();total integer;begin
 select count(*) into total from public.get_chat_summaries();
 if total<>${count} then raise exception 'Legacy baseline lost members';end if;
 raise notice 'PAGE_BENCH legacy_full ${sample} %',extract(epoch from clock_timestamp()-started)*1000;end $t$;
 `;
 source+=`do $p$declare plan json;begin
 execute $q$explain(analyze,buffers,format json)
 select coalesce(sum(unread_count),0)from private.chat_unread_counts
 where user_id='${owner}'and is_visible and not is_muted$q$into plan;
 raise notice 'UNREAD_TOTAL_PLAN %',plan::text;end $p$;
 explain(analyze,buffers,format json) select catalog.conversation_id,catalog.activity_at from private.chat_list_catalog catalog
 where catalog.user_id='${owner}' and catalog.is_visible
 and(catalog.activity_at,catalog.conversation_id)<(${cursor(tail)})
 order by catalog.activity_at desc,catalog.conversation_id desc limit 51;
 rollback;`;
 const r=sql(source);
 const samples=[...r.stderr.matchAll(/PAGE_BENCH (\w+) (\d+) ([\d.]+)/g)];assert.equal(samples.length,70);
 const times=[...Object.keys(cases),'direct_peer','unread_total','legacy_full'].map(name=>{const values=samples.filter(m=>m[1]===name&&+m[2]>=2).map(m=>+m[3]).sort((a,b)=>a-b);return{name,median_ms:values[2],max_ms:values.at(-1)};});
 const start=r.stdout.indexOf('[\n');assert(start>=0,'Missing EXPLAIN JSON');const plan=JSON.parse(r.stdout.slice(start))[0];
 writeFileSync(`tmp/chat_list_page_plan_${count}.json`,JSON.stringify(plan,null,2));
 const flatten=node=>[node,...(node.Plans??[]).flatMap(flatten)];
 const totalMarker=r.stderr.indexOf('UNREAD_TOTAL_PLAN ');assert(totalMarker>=0);
 const totalPlan=JSON.parse(r.stderr.slice(totalMarker+'UNREAD_TOTAL_PLAN '.length).trim())[0];
 const totalNodes=flatten(totalPlan.Plan);
 assert(totalNodes.every(node=>!['messages','message_receipts','message_hidden_for_users'].includes(node['Relation Name'])));
 const totalSeek=totalNodes.find(node=>node['Index Name']==='chat_unread_counts_badge_idx');
 // This synthetic owner has half of the entire metadata table. PostgreSQL
 // may correctly prefer its small sequential scan over the available index.
 // The invariant is metadata-only work, independent of message history size.
 const countsRead=totalNodes.find(node=>node['Relation Name']==='chat_unread_counts');
 assert(countsRead,'Missing metadata aggregate');assert.equal(countsRead['Actual Rows'],count);
 writeFileSync(`tmp/chat_unread_total_plan_${count}.json`,JSON.stringify(totalPlan,null,2));
 const seek=flatten(plan.Plan).find(node=>node['Index Name']==='chat_list_catalog_visible_order_idx');
 assert(seek,`Missing order index; inspect tmp/chat_list_page_plan_${count}.json`);
 assert.match(seek['Index Cond'],/ROW\(activity_at, conversation_id\) </);assert(seek['Actual Rows']<=51);
 rows.push({chats:count,messages:count*100,times,seek_actual_rows:seek['Actual Rows'],seek_shared_blocks:(seek['Shared Hit Blocks']??0)+(seek['Shared Read Blocks']??0),seek_plan:plan,unread_total_owner_index_used:!!totalSeek,unread_total_plan:totalPlan});
 assert.equal(snapshot(),before);
} } finally {
 // ANALYZE statistics and aborted tuple versions outlive transaction rollback.
 // Restore statistics of the real local data before subsequent SDK tests.
 sql('vacuum(analyze) public.messages,public.message_receipts,public.profiles,public.conversations,public.conversation_members,private.chat_list_catalog;');
 if(sql("select to_regclass('private.chat_unread_counts')is not null;").stdout.trim()==='t')sql('vacuum(analyze) private.chat_unread_counts,private.chat_unread_messages;');
}
const report={rows,fixtures_unchanged:true};writeFileSync('tmp/chat_list_page_benchmark.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
