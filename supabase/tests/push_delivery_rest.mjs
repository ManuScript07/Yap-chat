// Actual LOCAL PostgREST roles and production worker. Never contacts FCM.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { createPushHandler } from '../functions/push-message/worker.ts';
const url='http://127.0.0.1:54321';
function env(container) {
  const r=spawnSync('docker',['inspect','--format','{{json .Config.Env}}',container],{encoding:'utf8'});
  assert.equal(r.status,0,'Local Docker configuration unavailable');
  return Object.fromEntries(JSON.parse(r.stdout).map(item=>{const split=item.indexOf('=');return [item.slice(0,split),item.slice(split+1)];}));
}
const secret=env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const key=env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && key,'Local JWT configuration unavailable');
function token(sub,role='authenticated') {
  const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  const data=`${encode({alg:'HS256',typ:'JWT'})}.${encode({sub:sub??undefined,role,aud:'authenticated',exp:Math.floor(Date.now()/1000)+300})}`;
  return `${data}.${createHmac('sha256',secret).update(data).digest('base64url')}`;
}
function sql(input) {
  const result=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-U','postgres','-d','postgres','-X','-qAt','-v','ON_ERROR_STOP=1'],{input,encoding:'utf8',timeout:15000});
  assert.equal(result.status,0,result.stderr);
  return result.stdout.trim();
}
async function request(path,method,body,sub,role='authenticated',extra={}) {
  const response=await fetch(`${url}/rest/v1/${path}`,{method,headers:{apikey:key,Authorization:`Bearer ${token(sub,role)}`,'Content-Type':'application/json',...extra},
    body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
  const text=await response.text();
  return {status:response.status,ok:response.ok,data:text?JSON.parse(text):null};
}
const users=[randomUUID(),randomUUID()].sort(), chat=randomUUID(), message=randomUUID();
try {
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
    ('${users[0]}',false,false,'{}'),('${users[1]}',false,false,'{}');
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values('${chat}','${users[0]}','${users[1]}','${users[0]}');
    insert into public.conversation_members(conversation_id,user_id) values('${chat}','${users[0]}'),('${chat}','${users[1]}'); commit;`);
  for (let i=0;i<12;i++) {
    const r=await request('rpc/register_push_device','POST',{device_token:`rest-${users[1]}-${i}`,device_locale:'en'},users[1]);
    assert.ok(r.ok,`Registration REST ${r.status}`);
  }
  const own=await request('push_devices','GET',undefined,users[1]);
  assert.equal(own.data.length,10);
  assert.equal((await request('push_devices','GET',undefined,users[0])).data.length,0);
  for (const [method,body,extra] of [
    ['POST',{user_id:users[1],token:'direct-rest-token-00001'},{}],
    ['POST',[{user_id:users[1],token:'bulk-rest-token-000001'}],{}],
    ['POST',{user_id:users[1],token:own.data[0].token},{Prefer:'resolution=merge-duplicates'}],
    ['PATCH',{enabled:true},{}],['DELETE',undefined,{}],
  ]) {
    const path = ['PATCH','DELETE'].includes(method) ? `push_devices?id=eq.${own.data[0].id}` : 'push_devices';
    const denied=await request(path,method,body,users[1],'authenticated',extra);
    assert.ok(!denied.ok && [400,403].includes(denied.status),`${method}: ${JSON.stringify(denied.data)}`);
  }
  assert.ok(!(await request('rpc/register_push_device','POST',{device_token:'anonymous-rest-token-00001'},null,'anon')).ok);
  for (const [name,args] of [
    ['claim_push_notification',{outbox_id:randomUUID()}],
    ['get_due_push_notification_ids',{}],
    ['finish_push_notification',{outbox_id:randomUUID(),lease_token:randomUUID(),device_results:[]}],
  ]) assert.ok(!(await request(`rpc/${name}`,'POST',args,users[1])).ok);
  console.log('PASS: real PostgREST registration/select; single/bulk/upsert/update/delete bypass denied; worker APIs inaccessible to clients');
  assert.equal((await request('push_devices','GET',undefined,users[1])).data.length,10);
  // Tests normal logout RPC and re-registration, not direct table writes.
  assert.ok((await request('rpc/unregister_push_device','POST',{device_token:own.data[0].token},users[1])).ok);
  assert.ok((await request('rpc/register_push_device','POST',{device_token:own.data[0].token},users[1])).ok);
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text) values('${message}','${chat}','${users[0]}','text','REST worker contract');`);
  const outbox=sql(`select id from public.push_notification_outbox where message_id='${message}';`);
  let sends=0;
  const handler=createPushHandler({secret:'local',configured:true,
    createAdmin:()=>({rpc:async(name,args)=>{
      const r=await request(`rpc/${name}`,'POST',args,null,'service_role');
      return {data:r.data,error:r.ok?null:{message:`REST ${r.status}`}};
    }}),authorize:async()=>({projectId:'dummy',accessToken:'dummy'}),fetch:async()=>{sends++;return Response.json({name:'accepted'});}});
  const r=await handler(new Request('https://local/push',{method:'POST',headers:{'x-webhook-secret':'local'},body:JSON.stringify({outbox_id:outbox})}));
  assert.equal(r.status,200);
  assert.equal((await r.json()).status,'sent');
  assert.equal(sends,10);
  assert.equal(sql(`select delivered_device_count from public.push_notification_outbox where id='${outbox}';`),'10');
  console.log('PASS: worker through actual service-role REST with pre-request hook; 10 accepted devices and stored completion');
} finally {
  sql(`begin; delete from public.conversations where id='${chat}';
    delete from public.profiles where id in ('${users[0]}','${users[1]}');
    delete from auth.users where id in ('${users[0]}','${users[1]}'); commit;`);
}
