// Local Docker Supabase only. Reads local keys internally; never prints them.
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const url = 'http://127.0.0.1:54321';
function env(container) {
  const r = spawnSync('docker', ['inspect', '--format', '{{json .Config.Env}}', container], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('Local container unavailable');
  return Object.fromEntries(JSON.parse(r.stdout).map(v => [v.slice(0,v.indexOf('=')),v.slice(v.indexOf('=')+1)]));
}
const secret=env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anonKey=env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anonKey, 'Local JWT configuration missing');
function jwt(user) {
  const encode=v=>Buffer.from(JSON.stringify(v)).toString('base64url');
  const data=encode({alg:'HS256',typ:'JWT'})+'.'+encode({sub:user,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+300});
  return data+'.'+createHmac('sha256',secret).update(data).digest('base64url');
}
function sql(input) {
  const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{input,encoding:'utf8'});
  if(r.status!==0) throw new Error(r.stderr);
  return r.stdout.trim();
}
async function rpc(name,token,params) {
  const response=await fetch(`${url}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:anonKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(params),signal:AbortSignal.timeout(10000)});
  const text=await response.text(); const data=text ? JSON.parse(text) : null; assert(response.ok,`${name}: ${JSON.stringify(data)}`); return data;
}
function connect(user, topicUser=user) {
  return new Promise((resolve,reject)=>{
    const ws=new WebSocket(url.replace('http','ws')+`/realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0`);
    const events=[]; const timer=setTimeout(()=>{ws.close();reject(new Error('Join timeout'));},10000);
    ws.addEventListener('open',()=>ws.send(JSON.stringify({topic:`realtime:user:${topicUser}:chats`,event:'phx_join',ref:'1',payload:{config:{broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[],private:true},access_token:jwt(user)}})));
    ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('Realtime socket error'));});
    ws.addEventListener('message',({data})=>{
      const event=JSON.parse(data);
      if(event.event==='phx_reply' && event.ref==='1') {
        clearTimeout(timer);
        if(event.payload.status!=='ok') {ws.close();resolve({denied:true,ws,events});}
        else resolve({denied:false,ws,events});
      }
      if(event.event==='broadcast' && event.payload?.event==='presence_changed') events.push({at:performance.now(),payload:event.payload.payload});
    });
  });
}

const a=randomUUID(), b=randomUUID(), stranger=randomUUID();
const sessionA=randomUUID(), sessionB=randomUUID(), sockets=[];
const tokenA=jwt(a), tokenB=jwt(b);
async function waitForEvent(connection, userId, online, after=0) {
  const deadline=Date.now()+10000;
  while(!connection.events.slice(after).some(e=>e.payload.user_id===userId && e.payload.is_online===online)) {
    assert(Date.now()<deadline,'Presence broadcast missing'); await new Promise(r=>setTimeout(r,10));
  }
}
try {
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
    values ('${a}',false,false,'{}'),('${b}',false,false,'{}'),('${stranger}',false,false,'{}');
    insert into public.friendships(user_one_id,user_two_id)
    values(least('${a}'::uuid,'${b}'::uuid),greatest('${a}'::uuid,'${b}'::uuid)); commit;`);
  const first=await connect(a); sockets.push(first.ws); assert(!first.denied,'Own shared channel rejected');
  const foreign=await connect(stranger,a); sockets.push(foreign.ws); assert(foreign.denied,'Foreign channel readable');
  await rpc('touch_my_presence_session',tokenA,{target_session_id:sessionA});
  const params={target_session_id:sessionA,scope_key:'local-recovery',target_user_ids:[b]};
  assert.equal((await rpc('set_my_presence_watch_scope',tokenA,params))[0].is_online,false);
  await rpc('touch_my_presence_session',tokenB,{target_session_id:sessionB});
  await waitForEvent(first,b,true);
  await rpc('close_my_presence_session',tokenB,{target_session_id:sessionB});
  await waitForEvent(first,b,false);
  const closed=new Promise(resolve=>first.ws.addEventListener('close',resolve,{once:true}));
  first.ws.close(); await closed;
  // A changes while the watcher has no channel. The rejoin snapshot catches it.
  await rpc('touch_my_presence_session',tokenB,{target_session_id:sessionB});
  const resumed=await connect(a); sockets.push(resumed.ws); assert(!resumed.denied,'Rejoin rejected');
  assert.equal((await rpc('set_my_presence_watch_scope',tokenA,params))[0].is_online,true);
  await rpc('close_my_presence_session',tokenB,{target_session_id:sessionB});
  await waitForEvent(resumed,b,false);
  await rpc('touch_my_presence_session',tokenB,{target_session_id:sessionB});
  await waitForEvent(resumed,b,true);
  const previous=resumed.events.length;
  await rpc('block_user',tokenB,{target_user_id:a});
  await waitForEvent(resumed,b,false,previous);
  assert.equal((await rpc('set_my_presence_watch_scope',tokenA,params))[0].is_online,false);
  // The modified-client direct write is rejected by REST, not only SQL Editor.
  const direct=await fetch(`${url}/rest/v1/user_blocks`,{method:'POST',
    headers:{apikey:anonKey,Authorization:`Bearer ${tokenA}`,'Content-Type':'application/json'},
    body:JSON.stringify({blocker_user_id:a,blocked_user_id:stranger}),signal:AbortSignal.timeout(10000)});
  assert.equal(direct.status,403,'Raw block INSERT bypassed the RPC');
  console.log(JSON.stringify({passed:true,shared_channel_delivery:true,foreign_channel_denied:true,
    missed_event_recovered_by_snapshot:true,rejoined_channel_delivery:true,block_privacy:true,direct_rest_write_denied:true}));
} finally {
  for(const ws of sockets) ws.close();
  // Delete only this test's random fixtures; no application account is touched.
  sql(`begin; delete from public.profiles where id in ('${a}','${b}','${stranger}');
    delete from auth.users where id in ('${a}','${b}','${stranger}'); commit;`);
}
