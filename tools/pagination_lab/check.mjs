// Explicit fixture-only reset. Does not touch untagged local users or remote DBs.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {PaginationLab,root,literal} from './lab.mjs';

if(!process.argv.includes('--reset-fixture'))throw Error('Pass --reset-fixture to reset only the pagination fixture after testing');
const lab=new PaginationLab().connect();
lab.requireSeed();
const report={before:lab.status()};
const auth=await lab.session(lab.state.owner);
const events={chats:[],friends:[]},sockets=[];
async function connect(kind){
  return new Promise((resolve,reject)=>{
    const ws=new WebSocket(`${lab.api.replace('http:','ws:')}/realtime/v1/websocket?apikey=${encodeURIComponent(lab.key)}&vsn=1.0.0`);
    sockets.push(ws);
    const timer=setTimeout(()=>{ws.close();reject(Error('Local realtime join timed out'));},15000);
    ws.addEventListener('open',()=>ws.send(JSON.stringify({topic:`realtime:user:${lab.state.owner.id}:${kind}`,event:'phx_join',ref:'1',payload:{config:{broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[],private:true},access_token:auth.access_token}})));
    ws.addEventListener('message',({data})=>{const message=JSON.parse(data);if(message.event==='phx_reply'&&message.ref==='1'){clearTimeout(timer);if(message.payload.status==='ok')resolve();else reject(Error('Private realtime join denied'));}if(message.event==='broadcast')events[kind].push(message.payload);});
    ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('Local realtime connection failed'));});
  });
}
async function until(check){const deadline=Date.now()+10000;while(!check()){assert(Date.now()<deadline,'Expected realtime event was not delivered');await new Promise(r=>setTimeout(r,30));}}
const outsideEmail=`outside-${randomUUID()}@example.test`;
let outsider;
try {
  await Promise.all([connect('chats'),connect('friends')]);
  const old=await lab.action('old-chat-message');
  await until(()=>events.chats.some(e=>e.payload?.conversation_id===old.chatId));
  const head=await lab.rpc(lab.state.owner,'get_chat_list_page',{page_size:50,search_query:''},auth);
  assert.equal(head.items[0].id,old.chatId);
  const incoming=await lab.action('new-chat');
  await until(()=>events.chats.some(e=>e.payload?.conversation_id===incoming.chatId));
  assert.equal(lab.status().chats,report.before.chats+1);
  await lab.action('new-request');
  await until(()=>events.friends.length>0);
  assert.equal(lab.status().incoming,report.before.incoming+1);
  await lab.action('cancel-incoming');
  assert.equal(lab.status().incoming,report.before.incoming);
  await lab.action('accept-outgoing');
  assert.equal(lab.status().friends,report.before.friends+1);
  assert.equal(lab.status().outgoing,report.before.outgoing-1);
  report.realtime={chatEvents:events.chats.length,friendEvents:events.friends.length};
  const created=await lab.request('/auth/v1/admin/users',{method:'POST',body:{email:outsideEmail,password:lab.state.password,email_confirm:true,user_metadata:{name:'Outside fixture sentinel'}}});
  outsider=(created.user||created).id;
  const path=`${outsider}/keep.jpg`;
  await lab.request(`/storage/v1/object/avatars/${path}`,{method:'POST',bytes:readFileSync(join(root,'tools/pagination_lab/avatars/0.jpg')),contentType:'image/jpeg'});
  report.cleanup=await lab.cleanup();
  assert.equal(lab.data(`select count(*) from auth.users where id=${literal(outsider)};`),1);
  assert.equal(lab.data(`select count(*) from storage.objects where bucket_id='avatars' and name=${literal(path)};`),1);
  report.unrelatedUserAndFilePreserved=true;
  await lab.request('/storage/v1/object/avatars',{method:'DELETE',body:{prefixes:[path]}});
  await lab.request(`/auth/v1/admin/users/${outsider}`,{method:'DELETE'});
  outsider=null;
  report.clean=lab.data(`select jsonb_build_object('labUsers',(select count(*) from auth.users where raw_user_meta_data->>'pagination_lab'='yap-pagination-lab-v1'),'labStorage',(select count(*) from storage.objects where name like '%/pagination-%'));`);
  assert.equal(report.clean.labUsers,0);assert.equal(report.clean.labStorage,0);
} finally {
  sockets.forEach(ws=>ws.close());
  if(outsider) {
    await lab.request('/storage/v1/object/avatars',{method:'DELETE',body:{prefixes:[`${outsider}/keep.jpg`]}});
    await lab.request(`/auth/v1/admin/users/${outsider}`,{method:'DELETE'});
  }
}
report.restored=await lab.seed();
report.pages=await lab.verify();
await lab.prepare();
writeFileSync(join(lab.directory,'scenario-verification.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
