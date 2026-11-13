// Real HTTP + WebSocket, local Docker only. Random fixtures cleaned in finally.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
const url='http://127.0.0.1:54321';
function env(container) {
  const result=spawnSync('docker',['inspect','--format','{{json .Config.Env}}',container],{encoding:'utf8'});
  assert.equal(result.status,0,'Local container unavailable');
  return Object.fromEntries(JSON.parse(result.stdout).map(value=>{const p=value.indexOf('=');return [value.slice(0,p),value.slice(p+1)];}));
}
// Keys stay in memory; never printed or written to reports.
const secret=env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anon=env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anon);
function token(user) {
  const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  const data=`${encode({alg:'HS256',typ:'JWT'})}.${encode({sub:user,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+300})}`;
  return `${data}.${createHmac('sha256',secret).update(data).digest('base64url')}`;
}
function sql(source) {
  const result=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{
    input:`set statement_timeout='15s';\n${source}`,encoding:'utf8',timeout:20000,
  });
  assert.equal(result.status,0,result.stderr||String(result.error));return result.stdout.trim();
}
async function read(user,ids,expectedStatus=204) {
  const response=await fetch(`${url}/rest/v1/rpc/mark_conversations_read`,{
    method:'POST',headers:{apikey:anon,Authorization:`Bearer ${token(user)}`,'Content-Type':'application/json'},
    body:JSON.stringify({conversation_ids:ids}),signal:AbortSignal.timeout(15000),
  });
  assert.equal(response.status,expectedStatus,await response.text());
}
const sockets=[];
async function connect(user,owner=user) {
  return await new Promise((resolve,reject)=>{
    const ws=new WebSocket(`${url.replace('http','ws')}/realtime/v1/websocket?apikey=${encodeURIComponent(anon)}&vsn=1.0.0`);
    sockets.push(ws);const events=[];
    const timeout=setTimeout(()=>{ws.close();reject(Error('Realtime timed out'));},10000);
    ws.addEventListener('error',()=>{clearTimeout(timeout);reject(Error('Realtime transport error'));});
    ws.addEventListener('open',()=>ws.send(JSON.stringify({topic:`realtime:user:${owner}:chats`,event:'phx_join',ref:'1',payload:{
      config:{broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[],private:true},access_token:token(user),
    }})));
    ws.addEventListener('message',({data})=>{
      const event=JSON.parse(data);
      if(event.event==='phx_reply'&&event.ref==='1'){clearTimeout(timeout);resolve({events,denied:event.payload.status!=='ok'});}
      if(event.event==='broadcast'&&event.payload.payload?.reason==='read')events.push(event.payload.payload);
    });
  });
}
async function until(check) {
  const deadline=Date.now()+10000;
  while(!check()){assert(Date.now()<deadline,'Missing read event');await new Promise(resolve=>setTimeout(resolve,10));}
}
const owner=randomUUID(),peer=randomUUID(),other=randomUUID(),stranger=randomUUID();
const chats=[randomUUID(),randomUUID()],messages=[randomUUID(),randomUUID(),randomUUID()];
const users=[owner,peer,other,stranger];
const pair=p=>[owner,p].sort();
try {
  sql(`begin;
    insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values ${users.map(id=>`('${id}',false,false,'{}')`).join(',')};
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values
      ('${chats[0]}','${pair(peer)[0]}','${pair(peer)[1]}','${peer}'),('${chats[1]}','${pair(other)[0]}','${pair(other)[1]}','${other}');
    insert into public.conversation_members(conversation_id,user_id) values
      ('${chats[0]}','${owner}'),('${chats[0]}','${peer}'),('${chats[1]}','${owner}'),('${chats[1]}','${other}');
    insert into public.messages(id,conversation_id,sender_id,type,text) values
      ('${messages[0]}','${chats[0]}','${peer}','text','read fixture'),('${messages[1]}','${chats[1]}','${other}','text','read fixture');
    commit;`);
  const first=await connect(owner),second=await connect(owner),recipient=await connect(peer),otherRecipient=await connect(other),outsider=await connect(stranger);
  assert(!first.denied&&!second.denied&&!recipient.denied&&!otherRecipient.denied&&!outsider.denied);
  assert((await connect(stranger,owner)).denied,'Private owner channel exposed');
  await read(owner,chats);
  await until(()=>first.events.length===2&&second.events.length===2&&recipient.events.length===1&&otherRecipient.events.length===1);
  assert.deepEqual(new Set(first.events.map(event=>event.conversation_id)),new Set(chats));
  await read(owner,chats); // Accepted, but no work/event on repeated mark.
  await read(owner,Array(51).fill(chats[0]),400);
  await read(stranger,chats); // Not a member: no receipts and no broadcast.
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text) values('${messages[2]}','${chats[0]}','${peer}','text','arrived after read');`);
  assert.equal(sql(`select count(*) from public.message_receipts where message_id='${messages[2]}' and user_id='${owner}';`),'0');
  await Promise.all([read(owner,[chats[0]]),read(owner,[chats[0]])]);
  await until(()=>first.events.length===3&&second.events.length===3&&recipient.events.length===2);
  await new Promise(resolve=>setTimeout(resolve,450));
  assert.equal(first.events.length,3);assert.equal(second.events.length,3);
  assert.equal(recipient.events.length,2);assert.equal(otherRecipient.events.length,1);assert.equal(outsider.events.length,0);
  assert.equal(sql(`select count(*) from public.message_receipts where message_id in('${messages.join("','")}') and user_id='${owner}';`),'3');
  assert.equal(sql(`select count(*) from public.message_receipts where message_id in('${messages.join("','")}') and user_id<>'${owner}';`),'0');
  console.log(JSON.stringify({passed:true,owner_device_events:[3,3],peer_events:[2,1],outsider_events:0,no_op_events:0,concurrent_same_state_events:1,late_message_initially_unread:true,oversized_http_status:400}));
} finally {
  for(const ws of sockets)ws.close();
  sql(`begin;delete from public.conversations where id in('${chats.join("','")}');
    delete from public.profiles where id in('${users.join("','")}');delete from auth.users where id in('${users.join("','")}');commit;`);
  assert.equal(sql(`select count(*) from auth.users where id in('${users.join("','")}');`),'0');
}
