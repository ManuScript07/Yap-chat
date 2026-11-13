// Local Docker only; never calls Yandex or prints credentials. Two real handler
// instances use the project's PostgREST. Concurrent DB tests use a separate DB.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHmac, randomUUID } from 'node:crypto';
import { createYandexUserInfoHandler } from '../functions/yandex-userinfo/handler.ts';

const container = 'supabase_db_Yap_chat';
const database = 'yandex_userinfo_test_' + randomUUID().replaceAll('-','');
assert.match(database, /^yandex_userinfo_test_[a-f0-9]{32}$/);
function sql(input, db = 'postgres') {
  const r=spawnSync('docker',['exec','-i',container,'psql','-U','postgres','-d',db,'-X','-qAt','-v','ON_ERROR_STOP=1'],
    {input,encoding:'utf8',timeout:20000});
  assert.equal(r.status,0,r.stderr || 'local SQL failed');return r.stdout.trim();
}
function environment(name) {
  const r=spawnSync('docker',['inspect','--format','{{json .Config.Env}}',name],{encoding:'utf8',timeout:10000});
  assert.equal(r.status,0,'Local Supabase container unavailable');
  return Object.fromEntries(JSON.parse(r.stdout).map(s=>[s.slice(0,s.indexOf('=')),s.slice(s.indexOf('=')+1)]));
}
function concurrent(input) {
  return new Promise((resolve,reject)=>{
    const child=spawn('docker',['exec','-i',container,'psql','-U','postgres','-d',database,'-X','-qAt','-v','ON_ERROR_STOP=1']);
    let output='',errors='';const timer=setTimeout(()=>child.kill(),15000);
    child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>errors+=v);
    child.on('error',reject);child.on('close',code=>{
      clearTimeout(timer);if(code===0)resolve(JSON.parse(output.trim()));else reject(new Error(errors||'local SQL failed'));
    });child.stdin.end('set role service_role;'+input);
  });
}

const serviceKey=environment('supabase_storage_Yap_chat').SERVICE_KEY;
const anonKey=environment('supabase_storage_Yap_chat').ANON_KEY;
assert(serviceKey && anonKey,'Local API keys missing');
const localUrl='http://127.0.0.1:54321';
const token='fixture-'+randomUUID();
const hash=createHmac('sha256',serviceKey).update('yandex-userinfo:v1:'+token).digest('hex');
let upstreamCalls=0,quotaCalls=0;
const handler=()=>createYandexUserInfoHandler({supabaseUrl:localUrl,serviceRoleKey:serviceKey,
  fetch:async(url,init)=>{
    if(url.startsWith(localUrl+'/rest/v1/')){quotaCalls++;return fetch(url,init);}
    assert.equal(url,'https://login.yandex.ru/info?format=json');upstreamCalls++;
    return Response.json({id:'local-fixture',birthday:'2007-02-28',default_email:'fixture@example.test',is_avatar_empty:true});
  }});
const handlers=[handler(),handler()];
try {
  // ACL and service-only wrapper over actual PostgREST, not just SQL grants.
  const forbidden=await fetch(localUrl+'/rest/v1/rpc/consume_yandex_userinfo_quota',{
    method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+anonKey,'Content-Type':'application/json'},
    body:JSON.stringify({token_hash:hash}),signal:AbortSignal.timeout(5000)});
  assert.equal(forbidden.status,401);await forbidden.text();
  const results=await Promise.all(Array.from({length:16},(_,i)=>handlers[i%2](new Request('https://adapter.invalid',{
    headers:{authorization:(i%2?'OAuth ':'Bearer ')+token},
  }))));
  assert.equal(results.filter(r=>r.status===200).length,10);
  assert.equal(results.filter(r=>r.status===429).length,6);
  assert.equal(upstreamCalls,10);assert.ok(quotaCalls>10 && quotaCalls<=16);
  for(const r of results) await r.json();
  assert.equal(sql(`select request_count from private.yandex_userinfo_token_quota where token_hash='${hash}';`),'10');
  const afterDenial=quotaCalls;
  for(let i=0;i<100;i++) {
    const response=await handlers[i%2](new Request('https://adapter.invalid',{headers:{authorization:'Bearer '+token}}));
    assert.equal(response.status,429);await response.json();
  }
  assert.equal(quotaCalls,afterDenial);assert.equal(upstreamCalls,10);
  console.log('PASS: actual PostgREST ACL, shared admission exactly 10/16 and 100 cached denials without further RPCs.');

  sql(`create database ${database};`);
  sql('create schema private; grant usage on schema private to service_role;',database);
  sql(readFileSync(new URL('../migrations/202610120001_harden_yandex_userinfo.sql',import.meta.url),'utf8'),database);
  sql(readFileSync(new URL('./yandex_userinfo_quota.sql',import.meta.url),'utf8'),database);
  const reset=(global,perToken,cap)=>sql(`truncate private.yandex_userinfo_token_quota;
    update private.yandex_userinfo_quota set request_count=0,window_started_at=clock_timestamp(),
    global_limit=${global},token_limit=${perToken},max_token_keys=${cap};`,database);
  reset(100,7,6000);
  let batch=await Promise.all(Array.from({length:32},()=>concurrent(`select public.consume_yandex_userinfo_quota(repeat('a',64));`)));
  assert.equal(batch.filter(r=>r.allowed).length,7);
  assert.equal(sql('select request_count from private.yandex_userinfo_quota;',database),'7');
  reset(13,10,6000);
  batch=await Promise.all(Array.from({length:32},(_,i)=>concurrent(`select public.consume_yandex_userinfo_quota(lpad(to_hex(${i}),64,'0'));`)));
  assert.equal(batch.filter(r=>r.allowed).length,13);
  assert.equal(sql('select count(*) from private.yandex_userinfo_token_quota;',database),'13');
  reset(100,10,5);
  batch=await Promise.all(Array.from({length:32},(_,i)=>concurrent(`select public.consume_yandex_userinfo_quota(lpad(to_hex(${i}),64,'0'));`)));
  assert.equal(batch.filter(r=>r.allowed).length,5);
  assert.equal(sql('select count(*) from private.yandex_userinfo_token_quota;',database),'5');
  console.log('PASS: 96 concurrent transactions: token, rotating-token global and hard cardinality limits.');
  reset(10000,1000,6000);
  const milliseconds=sql(`do $$ declare t timestamptz:=clock_timestamp(); begin
    for i in 1..1000 loop perform public.consume_yandex_userinfo_quota(lpad(to_hex(i),64,'0')); end loop;
    perform set_config('test.yandex_elapsed_ms',(extract(epoch from clock_timestamp()-t)*1000)::text,false); end; $$;
    select current_setting('test.yandex_elapsed_ms');`,database);
  assert.equal(sql('select request_count from private.yandex_userinfo_quota;',database),'1000');
  console.log(`PASS: 1000 DB-only admissions in ${milliseconds} ms (not HTTP/network latency).`);
} finally {
  // Only this disposable test database and this exact mock token are removed.
  sql(`delete from private.yandex_userinfo_token_quota where token_hash='${hash}';`);
  if(sql(`select count(*) from pg_database where datname='${database}';`)==='1') sql(`drop database ${database} with (force);`);
}
