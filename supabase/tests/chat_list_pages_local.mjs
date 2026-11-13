// Real REST + Broadcast, local Docker only. Random fixture IDs, cleanup in finally.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHmac,randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
function env(container){const r=spawnSync('docker',['inspect','--format','{{json .Config.Env}}',container],{encoding:'utf8'});assert.equal(r.status,0);return Object.fromEntries(JSON.parse(r.stdout).map(v=>{const i=v.indexOf('=');return[v.slice(0,i),v.slice(i+1)];}));}
const secret=env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anon=env('supabase_storage_Yap_chat').ANON_KEY;assert(secret&&anon);
function token(user){const encode=v=>Buffer.from(JSON.stringify(v)).toString('base64url');const body=`${encode({alg:'HS256',typ:'JWT'})}.${encode({sub:user,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+600})}`;return`${body}.${createHmac('sha256',secret).update(body).digest('base64url')}`;}
function sql(query){const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input:`set statement_timeout='30s';\n${query}`,encoding:'utf8',timeout:40000,maxBuffer:4*1024*1024});assert.equal(r.status,0,r.stderr||String(r.error));return r.stdout.trim();}
async function rpc(user,name,params={}){const r=await fetch(`http://127.0.0.1:54321/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:anon,Authorization:`Bearer ${token(user)}`,'Content-Type':'application/json'},body:JSON.stringify(params),signal:AbortSignal.timeout(30000)});const text=await r.text();return{status:r.status,data:text?JSON.parse(text):null};}
const owner=randomUUID(),outsider=randomUUID();
const peers=Array.from({length:2005},()=>randomUUID()),chats=peers.map(()=>randomUUID());
const users=[owner,outsider,...peers],sockets=[];
const ids=values=>values.map(v=>`'${v}'`).join(',');
const counts=()=>sql("select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'catalog',(select count(*) from private.chat_list_catalog),'unread_keys',(select count(*)from private.chat_unread_messages),'unread_counts',(select count(*)from private.chat_unread_counts));");
const before=counts();const report={};
async function connect(user){return new Promise((resolve,reject)=>{const ws=new WebSocket(`ws://127.0.0.1:54321/realtime/v1/websocket?apikey=${encodeURIComponent(anon)}&vsn=1.0.0`);sockets.push(ws);const events=[];const timer=setTimeout(()=>{ws.close();reject(Error('join timed out'));},12000);
 ws.addEventListener('open',()=>ws.send(JSON.stringify({topic:`realtime:user:${user}:chats`,event:'phx_join',ref:'1',payload:{config:{broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[],private:true},access_token:token(user)}})));
 ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('local websocket error'));});
 ws.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.event==='phx_reply'&&m.ref==='1'){clearTimeout(timer);assert.equal(m.payload.status,'ok');resolve(events);}if(m.event==='broadcast'&&m.payload.payload?.reason==='insert')events.push(m.payload.payload);});
});}
async function until(check){const end=Date.now()+10000;while(!check()){assert(Date.now()<end,'missing broadcast');await new Promise(r=>setTimeout(r,20));}}
try {
 sql(`begin;insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values ${users.map(id=>`('${id}',false,false,'{}')`).join(',')};
 insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values ${chats.map((id,i)=>`('${id}',least('${owner}'::uuid,'${peers[i]}'::uuid),greatest('${owner}'::uuid,'${peers[i]}'::uuid),'${peers[i]}','2020-01-01 12:34:56.123456+00')`).join(',')};
 insert into public.conversation_members(conversation_id,user_id) values ${chats.flatMap((id,i)=>[`('${id}','${owner}')`,`('${id}','${peers[i]}')`]).join(',')};commit;`);
 const firstEvents=await connect(owner),secondEvents=await connect(owner);
 const legacy=await rpc(owner,'get_chat_summaries');assert.equal(legacy.status,200);assert.equal(legacy.data.length,1000);
 const loaded=[];let cursor=null,pages=0;
 do {
   const r=await rpc(owner,'get_chat_list_page',{after_activity_at:cursor?.activity_at??null,after_conversation_id:cursor?.conversation_id??null,page_size:50,search_query:''});
   assert.equal(r.status,200,JSON.stringify(r.data));assert(r.data.items.length<=50);assert.equal(r.data.unread_total,0);pages++;
   for(const item of r.data.items){assert.equal(item.list_activity_at,'2020-01-01T12:34:56.123456+00:00');loaded.push(item.id);}
   cursor=r.data.next_cursor;assert.equal(r.data.has_more,cursor!==null);assert(pages<50);
 }while(cursor);
 assert.deepEqual(loaded,[...chats].sort().reverse());assert.equal(new Set(loaded).size,2005);
 assert.equal(firstEvents.length,0);assert.equal(secondEvents.length,0);
 const oldest=chats.indexOf(loaded.at(-1));
 sql(`update public.profiles set display_name='Older Search Target' where id='${peers[oldest]}';`);
 const found=await rpc(owner,'get_chat_list_page',{search_query:'  OLDER  '});assert.equal(found.status,200);assert.deepEqual(found.data.items.map(v=>v.id),[chats[oldest]]);
 const beforeLookupQuota=JSON.parse(sql(`select jsonb_build_object('calls',request_count,'rows',requested_rows)from private.chat_summary_refresh_quota where user_id='${owner}';`));
 const peerLookup=await rpc(owner,'get_direct_chat_summary',{peer_user_id:peers[oldest]});assert.equal(peerLookup.status,200);assert.deepEqual(peerLookup.data.map(v=>v.id),[chats[oldest]]);
 const emptyLookup=await rpc(owner,'get_direct_chat_summary',{peer_user_id:randomUUID()});assert.equal(emptyLookup.status,200);assert.deepEqual(emptyLookup.data,[]);
 const afterLookupQuota=JSON.parse(sql(`select jsonb_build_object('calls',request_count,'rows',requested_rows)from private.chat_summary_refresh_quota where user_id='${owner}';`));
 assert.equal(afterLookupQuota.calls-beforeLookupQuota.calls,2);assert.equal(afterLookupQuota.rows-beforeLookupQuota.rows,2);
 const none=await rpc(outsider,'get_chat_list_page');assert.equal(none.status,200);assert.deepEqual(none.data.items,[]);assert.equal(none.data.unread_total,0);
 const mutationIds=chats.slice(0,10);const messageIds=mutationIds.map(()=>randomUUID());
 sql(`insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values ${mutationIds.map((id,i)=>`('${messageIds[i]}','${id}','${peers[i]}','text','page realtime test','2025-01-01'::timestamptz+${i}*interval '1 second')`).join(',')};`);
 await until(()=>firstEvents.length===10&&secondEvents.length===10);
 const head=await rpc(owner,'get_chat_list_page',{page_size:10});assert.equal(head.status,200);assert.deepEqual(head.data.items.map(v=>v.id),[...mutationIds].reverse());assert.equal(head.data.unread_total,10);
 const subset=await rpc(owner,'get_chat_unread_state',{conversation_ids:[chats[20]]});assert.equal(subset.status,200);assert.equal(subset.data.items[0].unread_count,0);assert.equal(subset.data.unread_total,10);
 const emptyState=await rpc(owner,'get_chat_unread_state');assert.equal(emptyState.status,200);assert.deepEqual(emptyState.data.items,[]);assert.equal(emptyState.data.unread_total,10);
 const outsiderState=await rpc(outsider,'get_chat_unread_state',{conversation_ids:[chats[0]]});assert.equal(outsiderState.status,200);assert.deepEqual(outsiderState.data,{items:[],unread_total:0});
 const hide=await rpc(owner,'hide_conversations',{conversation_ids:[chats[9]],cleared_before:new Date().toISOString()});assert(hide.status>=200&&hide.status<300);
 const noHidden=await rpc(owner,'get_chat_list_page',{page_size:10});assert.equal(noHidden.status,200);assert(!noHidden.data.items.some(v=>v.id===chats[9]));assert.equal(noHidden.data.unread_total,9);
 const restored=randomUUID();sql(`insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values('${restored}','${chats[9]}','${peers[9]}','text','restored incoming',clock_timestamp());`);
 await until(()=>firstEvents.length===11&&secondEvents.length===11);
 const afterRestore=await rpc(owner,'get_chat_list_page',{page_size:1});assert.equal(afterRestore.status,200);assert.equal(afterRestore.data.items[0].id,chats[9]);assert.equal(afterRestore.data.items[0].last_message_id,restored);assert.equal(afterRestore.data.unread_total,10);
 for(const muted of[true,false]){
  const changed=await rpc(owner,'set_conversations_muted',{conversation_ids:[chats[0]],muted});assert(changed.status>=200&&changed.status<300);
  const state=await rpc(owner,'get_chat_unread_state');assert.equal(state.status,200);assert.equal(state.data.unread_total,muted?9:10);
 }
 const invalid=await rpc(owner,'get_chat_list_page',{page_size:51});assert.equal(invalid.status,400);
 sql(`update private.chat_summary_refresh_quota set request_count=180 where user_id='${owner}';`);
 const lookupLimited=await rpc(owner,'get_direct_chat_summary',{peer_user_id:randomUUID()});assert.equal(lookupLimited.status,429);assert.equal(lookupLimited.data.message,'chat_summary_refresh_rate_limited');
 const unreadLimited=await rpc(owner,'get_chat_unread_state');assert.equal(unreadLimited.status,429);
 sql(`update private.chat_summary_refresh_quota set window_started_at=clock_timestamp()-interval '61 seconds' where user_id='${owner}';`);
 sql(`update private.chat_list_page_quota set request_count=120 where user_id='${owner}';`);
 const limited=await rpc(owner,'get_chat_list_page');assert.equal(limited.status,429);assert.equal(limited.data.message,'chat_list_page_rate_limited');
 sql(`update private.chat_list_page_quota set window_started_at=clock_timestamp()-interval '61 seconds' where user_id='${owner}';`);
 const recovered=await rpc(owner,'get_chat_list_page',{page_size:1});assert.equal(recovered.status,200);
 Object.assign(report,{passed:true,visible_chats:2005,legacy_http_rows:1000,pages,paged_rows:loaded.length,duplicates:loaded.length-new Set(loaded).size,microseconds_preserved:true,search_beyond_1000:true,outsider_rows:0,
   owner_device_insert_events:[firstEvents.length,secondEvents.length],metadata_reads_broadcasts:0,websockets:2,hide_and_incoming_restore:true,quota_http_status:429,
   peer_lookup_beyond_1000:true,empty_peer_lookup_charged_once:true,peer_quota_http_status:lookupLimited.status,
   global_unread_independent_of_page_and_subset:true,unread_hide_restore_mute:true,unread_quota_http_status:unreadLimited.status});
 console.log(JSON.stringify(report));
} finally {
 for(const socket of sockets)socket.close();
 sql(`begin;delete from public.conversations where user_one_id in(${ids(users)}) or user_two_id in(${ids(users)});delete from public.profiles where id in(${ids(users)});delete from auth.users where id in(${ids(users)});commit;`);
 assert.equal(counts(),before,'Local fixture counts changed');report.fixtures_cleaned=true;
 writeFileSync('tmp/chat_list_pages_rest.json',JSON.stringify(report,null,2));
}
