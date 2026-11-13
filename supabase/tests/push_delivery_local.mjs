// LOCAL Docker Supabase + actual Edge handler. FCM is mocked, never contacted.
// Run: node supabase/tests/push_delivery_local.mjs
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createPushHandler } from '../functions/push-message/worker.ts';

const args = ['exec','-i','supabase_db_Yap_chat','psql','-U','postgres','-d','postgres','-X','-qAt','-v','ON_ERROR_STOP=1'];
const users = [randomUUID(),randomUUID()].sort();
const chat = randomUUID();
const pending = new Set();
function sql(input) {
  const result = spawnSync('docker',args,{input,encoding:'utf8',timeout:15000});
  if (result.error || result.status) throw result.error ?? Error(result.stderr);
  return result.stdout.trim();
}
function parallel(input) {
  const child = spawn('docker',args);
  const result = new Promise((resolve,reject) => {
    let out='', err='';
    const timeout=setTimeout(()=>child.kill(),15000);
    child.stdout.on('data',data=>out+=data);
    child.stderr.on('data',data=>err+=data);
    child.on('error',reject);
    child.on('close',code=>{clearTimeout(timeout); code===0?resolve(out.trim()):reject(Error(err));});
    child.stdin.end(input);
  });
  pending.add(result);
  result.then(()=>pending.delete(result),()=>pending.delete(result));
  return result;
}
const literal = value => `'${String(value).replaceAll("'","''")}'`;
const scope = user => `select set_config('request.jwt.claim.sub','${user}',true); set local role authenticated;`;
const rpc = async (name, params) => {
  try {
    const parameters=Object.entries(params ?? {}).map(([key,value])=> value === null
      ? `${key}=>null`
      : `${key}=>${literal(typeof value==='object'?JSON.stringify(value):value)}${typeof value==='object'?'::jsonb':''}`).join(',');
    const output=sql(`begin; set local role service_role; select public.${name}(${parameters})::text; commit;`);
    return {data:JSON.parse(output),error:null};
  } catch(error) { return {data:null,error:{message:error.message}}; }
};
function newMessage() {
  const id=randomUUID();
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text) values('${id}','${chat}','${users[0]}','text','local push');`);
  return sql(`select id from public.push_notification_outbox where message_id='${id}';`);
}
try {
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
    ${users.map(id=>`('${id}',false,false,'{}')`).join(',')};
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values('${chat}','${users[0]}','${users[1]}','${users[0]}');
    insert into public.conversation_members(conversation_id,user_id) values('${chat}','${users[0]}'),('${chat}','${users[1]}'); commit;`);
  await Promise.all(Array.from({length:16},(_,i)=>parallel(`begin; set local statement_timeout='12s'; ${scope(users[1])}
    select public.register_push_device('concurrent-${users[1]}-${i}'); commit;`)));
  assert.equal(sql(`select count(*) from public.push_devices where user_id='${users[1]}';`),'10');
  console.log('PASS: 16 real concurrent registrations, exactly 10 devices');

  // A transfer is uncommitted while the old owner prunes its stale snapshot.
  // DELETE must recheck current ownership after waiting for the row lock.
  const transferToken=sql(`select token from public.push_devices where user_id='${users[1]}' order by last_seen_at,id limit 1;`);
  sql(`update public.push_devices set last_seen_at=now()-interval '1 day' where token=${literal(transferToken)};`);
  const appName=`push-transfer-${chat}`;
  const transfer=parallel(`begin; set local application_name='${appName}'; ${scope(users[0])}
    select public.register_push_device(${literal(transferToken)}); select pg_sleep(1.5); commit;`);
  let ready=false;
  const deadline=Date.now()+3000;
  while(Date.now()<deadline) {
    ready=sql(`select exists(select 1 from pg_stat_activity where application_name='${appName}' and wait_event='PgSleep');`)==='t';
    if(ready) break;
    await new Promise(resolve=>setTimeout(resolve,20));
  }
  assert.ok(ready,'Transfer transaction did not reach the intended lock state');
  const eviction=parallel(`begin; ${scope(users[1])} select public.register_push_device('eviction-${chat}'); commit;`);
  await Promise.all([transfer,eviction]);
  assert.equal(sql(`select user_id from public.push_devices where token=${literal(transferToken)};`),users[0],
    'Eviction of old owner deleted transferred device');
  console.log('PASS: concurrent transfer survives eviction by previous owner');

  sql(`delete from public.push_devices where user_id='${users[1]}';
    insert into public.push_devices(user_id,token) values('${users[1]}','integration-token-first-001'),('${users[1]}','integration-token-second-002');`);
  const outboxId=newMessage();
  const sends=[];
  let failSecond=true;
  const handler=createPushHandler({secret:'local-test',configured:true,createAdmin:()=>({rpc}),random:()=>0,
    authorize:async()=>({projectId:'dummy',accessToken:'dummy'}),fetch:async(_url,init)=>{
      const message=JSON.parse(init.body).message;
      sends.push(message.token);
      if (message.token.endsWith('002') && failSecond) return Response.json({}, {status:429,headers:{'Retry-After':'120'}});
      return Response.json({name:'mock-accepted'});
    }});
  const invoke = payload => handler(new Request('https://local/push', {method:'POST',headers:{'x-webhook-secret':'local-test'},body:JSON.stringify(payload)}));
  const first=await Promise.all([invoke({outbox_id:outboxId}),invoke({record:{id:outboxId,attempts:999}})]);
  assert.ok(first.every(response=>response.status===200));
  assert.equal(sends.length,2);
  assert.equal(sql(`select status||':'||attempts||':'||delivered_device_count from public.push_notification_outbox where id='${outboxId}';`),'pending:1:1');
  console.log('PASS: concurrent webhooks claim once; partial FCM progress persisted');
  failSecond=false;
  sql(`update public.push_notification_outbox set next_attempt_at=now()-interval '1 second' where id='${outboxId}';`);
  await invoke({retry_due:true});
  assert.equal(sends.filter(token=>token.endsWith('001')).length,1);
  assert.equal(sends.filter(token=>token.endsWith('002')).length,2);
  assert.equal(sql(`select status||':'||attempts||':'||delivered_device_count from public.push_notification_outbox where id='${outboxId}';`),'sent:2:2');
  console.log('PASS: actual scheduler/RPC/worker retries only rejected device');

  const stale=newMessage();
  sql(`delete from public.push_devices where user_id='${users[1]}';
    insert into public.push_devices(user_id,token) values('${users[1]}','fresh-installation-token-003');`);
  const before=sends.length;
  assert.equal((await (await invoke({outbox_id:stale})).json()).status,'no_devices');
  assert.equal(sends.length,before);
  const fresh=newMessage();
  await invoke({outbox_id:fresh});
  assert.equal(sends.at(-1),'fresh-installation-token-003');
  console.log('PASS: fresh installation skips old task, receives subsequent event');

  const networkJob=newMessage();
  const networkHandler=createPushHandler({secret:'local-test',configured:true,createAdmin:()=>({rpc}),
    authorize:async()=>({projectId:'dummy',accessToken:'dummy'}),fetch:async()=>{throw Error('network');}});
  const response=await networkHandler(new Request('https://local/push',{method:'POST',headers:{'x-webhook-secret':'local-test'},body:JSON.stringify({outbox_id:networkJob})}));
  assert.equal(response.status,200);
  assert.equal(sql(`select status from public.push_notification_outbox where id='${networkJob}';`),'pending');
  console.log('PASS: transport exception leaves durable pending task, not stuck processing');
} finally {
  await Promise.allSettled([...pending]);
  // Only random UUIDs created by this test. No DB reset / production access.
  sql(`begin; delete from public.conversations where id='${chat}';
    delete from public.profiles where id in (${users.map(literal).join(',')});
    delete from auth.users where id in (${users.map(literal).join(',')}); commit;`);
}
