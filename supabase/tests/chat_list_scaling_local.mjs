// Analysis-only probes. Local Docker/REST only; random fixtures cleaned in finally.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';

function env(container) {
  const r=spawnSync('docker',['inspect','--format','{{json .Config.Env}}',container],{encoding:'utf8'});
  assert.equal(r.status,0,'Local container unavailable');
  return Object.fromEntries(JSON.parse(r.stdout).map(s=>{const i=s.indexOf('=');return [s.slice(0,i),s.slice(i+1)];}));
}
// Secrets only in process memory, never in logs/reports.
const secret=env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anon=env('supabase_storage_Yap_chat').ANON_KEY;
const restEnv=env('supabase_rest_Yap_chat');
assert(secret&&anon);
function sql(query) {
  const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{
    input:`set statement_timeout='30s';\n${query}`,encoding:'utf8',timeout:35000,maxBuffer:4*1024*1024,
  });
  assert.equal(r.status,0,r.stderr||String(r.error));return r.stdout.trim();
}
function jwt(user) {
  const encode=v=>Buffer.from(JSON.stringify(v)).toString('base64url');
  const data=`${encode({alg:'HS256',typ:'JWT'})}.${encode({sub:user,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+600})}`;
  return `${data}.${createHmac('sha256',secret).update(data).digest('base64url')}`;
}
async function rpc(user,name,body={}) {
  const started=performance.now();
  const r=await fetch(`http://127.0.0.1:54321/rest/v1/rpc/${name}`,{
    method:'POST',headers:{apikey:anon,Authorization:`Bearer ${jwt(user)}`,'Content-Type':'application/json'},
    body:JSON.stringify(body),signal:AbortSignal.timeout(30000),
  });
  const text=await r.text();
  return {status:r.status,data:text?JSON.parse(text):null,bytes:Buffer.byteLength(text),ms:performance.now()-started};
}
const owner=randomUUID(),quotaUser=randomUUID(),newPeer=randomUUID();
const peers=Array.from({length:1001},()=>randomUUID());
const chats=peers.map(()=>randomUUID()),users=[owner,quotaUser,newPeer,...peers];
const created=[...chats];
const quoted=values=>values.map(v=>`'${v}'`).join(',');
const pair=p=>[owner,p].sort();
const report={};
const counts=()=>sql(`select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages));`);
const before=counts();
try {
  sql(`begin;
    insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values ${users.map(id=>`('${id}',false,false,'{}')`).join(',')};
    insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values
      ${chats.map((id,i)=>`('${id}','${pair(peers[i])[0]}','${pair(peers[i])[1]}','${peers[i]}','2020-01-01'::timestamptz+${i}*interval '1 second')`).join(',')};
    insert into public.conversation_members(conversation_id,user_id) values
      ${chats.flatMap((id,i)=>[`('${id}','${owner}')`,`('${id}','${peers[i]}')`]).join(',')};
    commit;`);
  assert.equal(sql(`select count(*) from public.conversation_members where user_id='${owner}' and hidden_at is null;`),'1001');
  const list=await rpc(owner,'get_chat_summaries');
  assert.equal(list.status,200);
  assert.equal(list.data.length,1000,'Expected the configured local API row cap');
  report.api_truncation={database_visible_chats:1001,http_rows:list.data.length,bytes:list.bytes,elapsed_ms:+list.ms.toFixed(2),configured_max_rows:restEnv.PGRST_DB_MAX_ROWS??'unset'};

  const existing=await rpc(owner,'create_direct_conversation',{peer_user_id:peers[0]});
  assert.equal(existing.status,200);assert.equal(existing.data,chats[0]);
  const blockedCreation=await rpc(owner,'create_direct_conversation',{peer_user_id:newPeer});
  assert.equal(blockedCreation.data.message,'chat_limit_reached');
  const incoming=await rpc(newPeer,'create_direct_conversation',{peer_user_id:owner});
  assert.equal(incoming.status,200);assert.equal(typeof incoming.data,'string');created.push(incoming.data);
  assert.equal(sql(`select count(*) from public.conversation_members where user_id='${owner}' and hidden_at is null;`),'1002');
  const hide=await rpc(owner,'hide_conversations',{conversation_ids:[chats[0]],cleared_before:new Date().toISOString()});
  assert(hide.status>=200&&hide.status<300,JSON.stringify(hide));
  assert.equal(sql(`select hidden_at is not null from public.conversation_members where conversation_id='${chats[0]}' and user_id='${owner}';`),'t');
  const reopen=await rpc(owner,'create_direct_conversation',{peer_user_id:peers[0]});
  assert.equal(reopen.data.message,'chat_limit_reached');
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values('${randomUUID()}','${chats[0]}','${peers[0]}','text','incoming restores hidden fixture',clock_timestamp());`);
  assert.equal(sql(`select hidden_at is null from public.conversation_members where conversation_id='${chats[0]}' and user_id='${owner}';`),'t');
  report.incoming_limit={existing_chat_accessible:true,outgoing_creation_denied:true,incoming_chat_created_above_limit:true,hidden_outgoing_restore_denied:true,incoming_message_restored_hidden:true,visible_after_incoming:1002};

  // Ten concurrent HTTP requests use the PostgREST pool; no per-chat DB session.
  const loadStarted=performance.now();
  const inflight=Array.from({length:10},()=>rpc(owner,'get_chat_summaries'));
  const backendCounts=[];
  let finished=false;
  // Handle rejection immediately so a transport timeout still reaches finally.
  const complete=Promise.all(inflight).then(results=>({results}),error=>({error})).finally(()=>{finished=true;});
  while(!finished) {
    backendCounts.push(Number(sql("select count(*) from pg_stat_activity where application_name like 'PostgREST%';")));
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  const outcome=await complete;
  if(outcome.error)throw outcome.error;
  const concurrent=outcome.results;
  for(const result of concurrent) {assert.equal(result.status,200);assert.equal(result.data.length,1000);}
  const durations=concurrent.map(r=>r.ms).sort((a,b)=>a-b);
  report.parallel_http={requests:10,rows_per_response:1000,total_ms:+(performance.now()-loadStarted).toFixed(2),median_ms:+durations[5].toFixed(2),max_ms:+durations.at(-1).toFixed(2),max_observed_postgrest_backends:Math.max(...backendCounts)};

  // API cap must not make an unrelated user see these memberships.
  const outsider=await rpc(quotaUser,'get_chat_summaries');
  assert.equal(outsider.status,200);assert.deepEqual(outsider.data,[]);
  const responses=[outsider];
  for(let i=1;i<31;i++)responses.push(await rpc(quotaUser,'get_chat_summaries'));
  assert.equal(responses.filter(r=>r.status===200).length,30);
  assert.equal(responses.at(-1).data.message,'network_read_rate_limited');
  report.quota={accepted:30,rejected:1,last_http_status:responses.at(-1).status,last_code:responses.at(-1).data.code,outsider_rows:0};
  report.postgrest_pool={configured_max:restEnv.PGRST_DB_POOL??'default',current_backends:Number(sql("select count(*) from pg_stat_activity where application_name like 'PostgREST%';"))};
  console.log(JSON.stringify(report));
} finally {
  sql(`begin;delete from public.conversations where id in(${quoted(created)})
      or user_one_id in(${quoted(users)}) or user_two_id in(${quoted(users)});
    delete from public.profiles where id in(${quoted(users)});delete from auth.users where id in(${quoted(users)});commit;`);
  assert.equal(counts(),before,'Local fixture counts changed');
  report.fixtures_cleaned=true;
  writeFileSync('tmp/chat_list_scaling_local.json',JSON.stringify(report,null,2));
}
