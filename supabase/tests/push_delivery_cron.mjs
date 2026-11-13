// LOCAL pg_cron -> pg_net -> HTTP -> production worker -> PostgreSQL.
// A short-lived authenticated HTTP listener replaces only the FCM transport.
// The two temporary Vault values and exact random fixtures are removed finally.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createPushHandler } from '../functions/push-message/worker.ts';
const users=[randomUUID(),randomUUID()].sort(), chat=randomUUID(), secret=randomUUID();
const vaultIds=[], jobs=[];
const literal=value=>`'${String(value).replaceAll("'","''")}'`;
function sql(input) {
  const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-U','postgres','-d','postgres','-X','-qAt','-v','ON_ERROR_STOP=1'],{input,encoding:'utf8',timeout:15000});
  if (r.error || r.status) throw r.error ?? Error(r.stderr);
  return r.stdout.trim();
}
const rpc=async(name,args)=>{
  try {
    const params=Object.entries(args??{}).map(([key,value])=>value===null?`${key}=>null`:
      `${key}=>${literal(typeof value==='object'?JSON.stringify(value):value)}${typeof value==='object'?'::jsonb':''}`).join(',');
    return {data:JSON.parse(sql(`begin; set local role service_role; select public.${name}(${params})::text; commit;`)),error:null};
  } catch { return {data:null,error:{message:'local_rpc_failed'}}; }
};
let requests=0, completed=0, rejectFcm=true, fcm=0;
const handler=createPushHandler({secret,configured:true,createAdmin:()=>({rpc}),random:()=>0,
  authorize:async()=>({projectId:'dummy',accessToken:'dummy'}),fetch:async()=>{
    fcm++;return rejectFcm?Response.json({}, {status:503}):Response.json({name:'accepted'});
  }});
const server=createServer(async(req,res)=>{
  requests++;
  try {
    const parts=[]; for await (const part of req) parts.push(part);
    const response=await handler(new Request('http://local/functions/v1/push-message',{
      method:req.method,headers:{'x-webhook-secret':req.headers['x-webhook-secret']??''},body:Buffer.concat(parts).toString(),
    }));
    res.writeHead(response.status,{'Content-Type':'application/json'});res.end(await response.text());
  } catch { res.writeHead(500);res.end('{}'); }
  finally { completed++; }
});
async function waitFor(check, timeout) {
  const deadline=Date.now()+timeout;
  while(!check()) {
    if(Date.now()>deadline) throw Error('Local cron/pg_net dispatch timed out');
    await new Promise(resolve=>setTimeout(resolve,100));
  }
}
try {
  assert.equal(sql(`select count(*) from vault.secrets where name in ('push_delivery_project_url','push_delivery_webhook_secret');`),'0',
    'Refusing to overwrite existing local recovery credentials');
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
    ('${users[0]}',false,false,'{}'),('${users[1]}',false,false,'{}');
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values('${chat}','${users[0]}','${users[1]}','${users[0]}');
    insert into public.conversation_members(conversation_id,user_id) values('${chat}','${users[0]}'),('${chat}','${users[1]}');
    insert into public.push_devices(user_id,token,registered_at) values('${users[1]}','cron-integration-token-001',now()-interval '1 day');
    insert into public.messages(id,conversation_id,sender_id,type,text) values(gen_random_uuid(),'${chat}','${users[0]}','text','cron fixture'); commit;`);
  jobs.push(sql(`select id from public.push_notification_outbox where conversation_id='${chat}';`));
  // Simulate an interrupted worker with an expired lease. The actual cron
  // schedule must discover and recover it without a manually invoked handler.
  sql(`select public.claim_push_notification('${jobs[0]}');
    update public.push_notification_outbox set lease_until=now()-interval '1 second' where id='${jobs[0]}';`);
  await new Promise(resolve=>server.listen(0,'0.0.0.0',resolve));
  const port=server.address().port;
  vaultIds.push(sql(`select vault.create_secret('http://host.docker.internal:${port}','push_delivery_project_url');`));
  vaultIds.push(sql(`select vault.create_secret(${literal(secret)},'push_delivery_webhook_secret');`));
  assert.equal(sql(`select active from cron.job where jobname='retry-push-notifications';`),'t');
  console.log('Waiting for one real local pg_cron tick (up to 65 seconds)...');
  await waitFor(()=>completed>=1,65000);
  assert.equal(sql(`select status||':'||attempts from public.push_notification_outbox where id='${jobs[0]}';`),'pending:2');
  assert.equal(fcm,1);
  console.log('PASS: real pg_cron/pg_net discovers expired lease; 503 becomes scheduled pending retry');
  rejectFcm=false;
  sql(`update public.push_notification_outbox set next_attempt_at=now()-interval '1 second' where id='${jobs[0]}';`);
  // Execute the exact stored cron SQL to avoid another minute-long wait.
  const command=sql(`select command from cron.job where jobname='retry-push-notifications';`);
  sql(command);
  await waitFor(()=>completed>=2,10000);
  assert.equal(sql(`select status||':'||attempts||':'||delivered_device_count from public.push_notification_outbox where id='${jobs[0]}';`),'sent:3:1');
  console.log('PASS: same cron dispatch retries through HTTP and stores successful completion');
  const before=requests;
  sql(command);
  await new Promise(resolve=>setTimeout(resolve,1500));
  assert.equal(requests,before);
  console.log('PASS: no HTTP request from idle queue');
} finally {
  // Remove only values this test created, before closing its listener.
  if(vaultIds.length) sql(`delete from vault.secrets where id in (${vaultIds.map(literal).join(',')});`);
  await new Promise(resolve=>server.close(resolve));
  sql(`begin; delete from public.conversations where id='${chat}';
    delete from public.profiles where id in ('${users[0]}','${users[1]}');
    delete from auth.users where id in ('${users[0]}','${users[1]}'); commit;`);
}
