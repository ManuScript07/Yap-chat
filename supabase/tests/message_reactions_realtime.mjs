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
  const data=await response.json(); assert(response.ok,`${name}: ${JSON.stringify(data)}`); return data;
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
      if(event.event==='broadcast' && event.payload.payload?.reason==='reaction_changed') events.push({at:performance.now(),payload:event.payload.payload});
    });
  });
}
const [a,b]=[randomUUID(),randomUUID()].sort(); const stranger=randomUUID(),chat=randomUUID(),message=randomUUID();
const sockets=[];
try {
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values ('${a}',false,false,'{}'),('${b}',false,false,'{}'),('${stranger}',false,false,'{}');
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values('${chat}','${a}','${b}','${a}');
    insert into public.conversation_members(conversation_id,user_id) values('${chat}','${a}'),('${chat}','${b}');
    insert into public.messages(id,conversation_id,sender_id,type,text) values('${message}','${chat}','${a}','text','local reaction test'); commit;`);
  const first=await connect(a); sockets.push(first.ws);
  const second=await connect(b); sockets.push(second.ws);
  assert(!first.denied && !second.denied,'Member channel rejected');
  const foreign=await connect(stranger,a); sockets.push(foreign.ws); assert(foreign.denied,'Foreign private channel was readable');
  const start=performance.now();
  const result=await rpc('set_message_reaction',jwt(b),{target_conversation_id:chat,target_message_id:message,reaction_code:'heart',operation_id:randomUUID(),expected_user_revision:0});
  assert.equal(result.state.version,1);
  assert.equal(result.state.reactions[0].position,1);
  const deadline=Date.now()+10000;
  while(!first.events.length || !second.events.length) {
    assert(Date.now()<deadline,'Reaction broadcast missing'); await new Promise(r=>setTimeout(r,10));
  }
  assert.equal(first.events[0].payload.message_id,message);
  assert.equal(second.events[0].payload.reaction_state.reactions[0].code,'heart');
  assert.equal(second.events[0].payload.reaction_state.reactions[0].position,1);
  const page=await rpc('get_conversation_message_window',jwt(a),{target_conversation_id:chat,target_message_id:message});
  assert.equal(page[0].reaction_state.reactions[0].code,'heart');
  await rpc('set_message_reaction',jwt(b),{target_conversation_id:chat,target_message_id:message,reaction_code:'heart',operation_id:randomUUID(),expected_user_revision:1});
  await new Promise(r=>setTimeout(r,100));
  assert.equal(first.events.length,1); assert.equal(second.events.length,1);
  assert.equal(Number(sql(`select count(*) from public.push_notification_outbox where reaction_message_id='${message}';`)),1);
  console.log(JSON.stringify({passed:true,member_events:[first.events.length,second.events.length],foreign_channel_denied:true,no_op_events:0,
    author_delivery_ms:Math.round(first.events[0].at-start),peer_delivery_ms:Math.round(second.events[0].at-start),reaction_pushes:1}));
} finally {
  for(const ws of sockets) ws.close();
  sql(`begin; delete from public.conversations where id='${chat}'; delete from public.profiles where id in ('${a}','${b}','${stranger}'); delete from auth.users where id in ('${a}','${b}','${stranger}'); commit;`);
}
