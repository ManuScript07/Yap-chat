// Real production handler, mocked transports: no network, tokens or user data.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createHmac } from 'node:crypto';
import { createYandexUserInfoHandler } from '../functions/yandex-userinfo/handler.ts';

const key = 'test-server-credential';
const fullUser = {
  id: 'fixture', login: 'login', default_email: 'a@example.test', emails: ['b@example.test'],
  real_name: 'Real', display_name: 'Display', birthday: '2007-02-28',
  default_avatar_id: '123/fixture', is_avatar_empty: false,
  default_phone: { number: ' +79990000000 ' },
};
function fixture(options = {}) {
  const calls = [];
  const handler = createYandexUserInfoHandler({
    supabaseUrl: 'https://database.invalid/', serviceRoleKey: key,
    quotaTimeoutMs: 100, upstreamTimeoutMs: 100,
    fetch: async (url, init) => {
      calls.push({url, init});
      assert.equal(init.redirect, 'error');
      assert.ok(init.signal instanceof AbortSignal);
      if (url.startsWith('https://database.invalid/')) {
        assert.equal(init.method, 'POST');
        assert.equal(init.headers.Authorization, 'Bearer ' + key);
        assert.match(JSON.parse(init.body).token_hash, /^[a-f0-9]{64}$/);
        assert.ok(!init.body.includes('sample-token'));
        return options.quota ? options.quota(init) : Response.json({allowed:true,retry_after_seconds:0});
      }
      assert.equal(url, 'https://login.yandex.ru/info?format=json');
      return options.upstream ? options.upstream(init) : Response.json(options.user ?? fullUser);
    },
    ...options.deps,
  });
  const invoke = (authorization = 'Bearer sample-token', extra = {}) => handler(new Request('https://adapter.invalid', {
    headers: authorization === null ? {} : {authorization}, ...extra,
  }));
  return {handler, invoke, calls};
}

for (const method of ['POST','DELETE','HEAD','OPTIONS','PUT','PATCH']) {
  test(`rejects ${method} before quota or upstream`, async () => {
    const f = fixture(); const r = await f.invoke('Bearer sample-token',{method});
    assert.equal(r.status,405); assert.equal(r.headers.get('allow'),'GET');
    assert.equal(r.headers.get('cache-control'),'no-store'); assert.equal(f.calls.length,0);
  });
}
for (const value of [null, '', 'Basic sample', 'sample', 'Bearer', 'OAuth', 'Bearer a b',
  'Bearer a,b', 'Bearer a\tb', 'Bearer a@b', 'Bearer =', 'Bearer a=b', 'Bearer '+ 'a'.repeat(4097)]) {
  test(`invalid credential ${value?.slice(0,30)} is rejected without network`, async () => {
    const f = fixture(); assert.equal((await f.invoke(value)).status,401); assert.equal(f.calls.length,0);
  });
}
test('query, body declarations, header and URL bounds are rejected cheaply', async () => {
  const f = fixture();
  for (const headers of [{'content-length':'1'}, {'content-length':'-1'}, {'transfer-encoding':'chunked'}]) {
    assert.equal((await f.invoke('Bearer sample-token',{headers:{authorization:'Bearer sample-token',...headers}})).status,400);
  }
  assert.equal((await f.handler(new Request('https://adapter.invalid?oauth_token=sample', {headers:{authorization:'Bearer sample-token'}}))).status,400);
  assert.equal((await f.handler(new Request('https://adapter.invalid/'+'a'.repeat(2048)))).status,431);
  assert.equal((await f.invoke('Bearer sample-token',{headers:{authorization:'Bearer sample-token','x-large':'é'.repeat(5000)}})).status,431);
  assert.equal(f.calls.length,0);
});
test('normal claims and nullish fallback priorities remain unchanged', async () => {
  const f = fixture(); const r = await f.invoke(); assert.equal(r.status,200);
  assert.deepEqual(await r.json(), {
    sub:'fixture',id:'fixture',email:'a@example.test',email_verified:true,name:'Real',preferred_username:'login',
    picture:'https://avatars.yandex.net/get-yapic/123/fixture/islands-200',
    birthdate:'2007-02-28',birthday:'2007-02-28',phone:'+79990000000',phone_verified:true,
    phone_number:'+79990000000',phone_number_verified:true,
  });
  assert.equal(r.headers.get('cache-control'),'no-store');
  assert.equal(f.calls.length,2);
  assert.equal(f.calls[1].init.headers.Authorization,'OAuth sample-token');
});
test('schemes/case/spaces share the same fingerprint; RFC bearer alphabet accepted', async () => {
  const f = fixture();
  for (const header of ['Bearer sample-token','OAuth sample-token','bEaReR   sample-token']) assert.equal((await f.invoke(header)).status,200);
  const hashes = f.calls.filter(c => c.init.body).map(c => JSON.parse(c.init.body).token_hash);
  assert.equal(new Set(hashes).size,1);
  assert.equal(hashes[0],createHmac('sha256',key).update('yandex-userinfo:v1:sample-token').digest('hex'));
  assert.equal((await f.invoke('Bearer a._~+/-==')).status,200);
  assert.equal((await f.invoke('OAuth SAMPLE-token')).status,200);
  assert.notEqual(JSON.parse(f.calls.at(-2).init.body).token_hash,hashes[0]);
});
for (const empty of [true, null, undefined]) {
  test(`Yandex empty/unknown avatar flag ${empty} never restores an avatar`, async () => {
    const f=fixture({user:{id:'fixture',default_avatar_id:'123/fixture',is_avatar_empty:empty}});
    const body=await (await f.invoke()).json(); assert.equal(body.picture,null);
    assert.equal(body.email,null); assert.equal(body.phone,null); assert.equal(body.birthdate,null);
  });
}
test('fallback email/name/partial birthday and empty phone mapping preserved', async () => {
  const f=fixture({user:{id:'fixture',emails:['fallback@example.test'],display_name:'Display',birthday:'0000-02-28',default_phone:{number:' '}}});
  const body=await (await f.invoke()).json(); assert.equal(body.email,'fallback@example.test'); assert.equal(body.name,'Display');
  assert.equal(body.birthdate,'0000-02-28'); assert.equal(body.phone_verified,false);
});
test('missing server config fails closed', async () => {
  const f=fixture({deps:{serviceRoleKey:undefined}}); assert.equal((await f.invoke()).status,503); assert.equal(f.calls.length,0);
});
test('quota denial returns retry information and never calls Yandex', async () => {
  const f=fixture({quota:()=>Response.json({allowed:false,retry_after_seconds:12})});
  const r=await f.invoke(); assert.equal(r.status,429); assert.equal(r.headers.get('retry-after'),'12'); assert.equal(f.calls.length,1);
});
test('1000 repeated denials use one RPC; expiry rechecks the server', async () => {
  let time=0;
  const f=fixture({deps:{now:()=>time},quota:()=>Response.json({allowed:false,retry_after_seconds:12,scope:'token'})});
  for(let i=0;i<1000;i++) assert.equal((await f.invoke(i%2?'OAuth sample-token':'Bearer sample-token')).status,429);
  assert.equal(f.calls.length,1);
  time=11001;
  assert.equal((await f.invoke()).headers.get('retry-after'),'1');
  time=12000;
  assert.equal((await f.invoke()).status,429);assert.equal(f.calls.length,2);
});
test('token denial does not block other credentials; only global denial does',async()=>{
  const f=fixture({quota:()=>Response.json({allowed:false,retry_after_seconds:30,scope:'token'})});
  await f.invoke(); await f.invoke('Bearer another-token');assert.equal(f.calls.length,2);
  let time=0;
  const g=fixture({deps:{now:()=>time},quota:()=>Response.json({allowed:false,retry_after_seconds:30,scope:'global'})});
  await g.invoke();
  for(let i=0;i<100;i++) assert.equal((await g.invoke('Bearer rotated-'+i)).status,429);
  assert.equal(g.calls.length,1);
  time=30000;await g.invoke('Bearer rotated-again');assert.equal(g.calls.length,2);
});
test('denial fingerprint cache stays bounded without granting admission on eviction',async()=>{
  const f=fixture({quota:()=>Response.json({allowed:false,retry_after_seconds:60,scope:'token'})});
  for(let i=0;i<1025;i++) assert.equal((await f.invoke('Bearer rotated-'+i)).status,429);
  await f.invoke('Bearer rotated-1024');assert.equal(f.calls.length,1025);
  assert.equal((await f.invoke('Bearer rotated-0')).status,429);assert.equal(f.calls.length,1026);
});
test('database outage sheds repeated requests briefly, then rechecks',async()=>{
  let time=0;
  const f=fixture({deps:{now:()=>time},quota:()=>new Response(null,{status:503})});
  for(let i=0;i<100;i++) assert.equal((await f.invoke('Bearer token-'+i)).status,503);
  assert.equal(f.calls.length,1);
  time=1000;await f.invoke();assert.equal(f.calls.length,2);
});
test('burst in-flight database work is bounded and permits recover after completion',async()=>{
  let release;
  const gate=new Promise(resolve=>{release=resolve;});
  const f=fixture({quota:async()=>{await gate;return Response.json({allowed:false,retry_after_seconds:10,scope:'token'});},
    deps:{quotaTimeoutMs:2000}});
  const requests=Array.from({length:100},(_,i)=>f.invoke('Bearer token-'+i));
  // Wait until hashing completes and the gate holds the accepted RPCs.
  await new Promise(resolve=>setTimeout(resolve,30));
  assert.equal(f.calls.length,64);
  release();
  const results=await Promise.all(requests);
  assert.equal(results.filter(r=>r.status===503).length,36);
  assert.equal(results.filter(r=>r.status===429).length,64);
  assert.equal((await f.invoke('Bearer new-token')).status,429);assert.equal(f.calls.length,65);
});
for (const quota of [()=>Response.json({sensitive:'secret'},{status:500}), ()=>{throw Error('secret');},
  ()=>Response.json({allowed:true}), ()=>Response.json({allowed:false,retry_after_seconds:0}),
  ()=>Response.json({allowed:true,retry_after_seconds:99}), ()=>Response.json({allowed:false,retry_after_seconds:30,scope:'unexpected'}), ()=>new Response('not json'),
  ()=>new Response('a'.repeat(1025))]) {
  test('unavailable or malformed quota never bypasses admission',async()=>{
    const f=fixture({quota});const r=await f.invoke(); assert.equal(r.status,503); assert.equal(f.calls.length,1);
    assert.deepEqual(await r.json(),{error:'yandex_userinfo_unavailable'});
  });
}
for (const value of [null, [], {}, {id:42}, {id:' '}, {id:'x',emails:[42]}, {id:'x',default_phone:'phone'},
  {id:'x',birthday:2007}, {id:'x',is_avatar_empty:'false'}, {id:'x',default_phone:{number:42}}]) {
  test('invalid upstream shapes fail safely',async()=>{
    const f=fixture({user:value,upstream:()=>Response.json(value)});
    assert.equal((await f.invoke()).status,502);
  });
}
for (const [status, expected] of [[401,401],[403,403],[429,503],[500,502],[302,502]]) {
  test(`upstream failure ${status} is sanitized without retry`,async()=>{
    const f=fixture({upstream:()=>new Response('secret',{status})}); const r=await f.invoke();
    assert.equal(r.status,expected); assert.deepEqual(await r.json(),{error:'yandex_userinfo_failed'}); assert.equal(f.calls.length,2);
  });
}
test('upstream byte bounds include streaming, content-length, UTF-8 and malformed JSON',async()=>{
  for (const upstream of [()=>new Response('x'.repeat(16385)),
    ()=>new Response('{}',{headers:{'content-length':'20000'}}),
    ()=>new Response(new Uint8Array([0xff])),()=>new Response('{')]) {
    const f=fixture({upstream}); assert.equal((await f.invoke()).status,502);
  }
});
for (const stage of ['quota','upstream']) {
  test(`${stage} timeout aborts fetch and never retries`,async()=>{
    let signal;
    const f=fixture({[stage]:init=>{signal=init.signal;return new Promise(()=>{});},deps:{quotaTimeoutMs:10,upstreamTimeoutMs:10}});
    const started=Date.now(),r=await f.invoke(); assert.equal(r.status,stage==='quota'?503:504);
    assert.ok(signal.aborted); assert.ok(Date.now()-started<500); assert.equal(f.calls.length,stage==='quota'?1:2);
  });
  test(`${stage} timeout also cancels a stalled response body`,async()=>{
    let cancelled=false;
    const f=fixture({[stage]:()=>new Response(new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('{'));},cancel(){cancelled=true;}})),
      deps:{quotaTimeoutMs:10,upstreamTimeoutMs:10}});
    assert.equal((await f.invoke()).status,stage==='quota'?503:504); assert.ok(cancelled);
  });
}
test('already cancelled request makes no transport call',async()=>{
  const f=fixture();const controller=new AbortController();controller.abort();
  assert.equal((await f.invoke('Bearer sample-token',{signal:controller.signal})).status,503);assert.equal(f.calls.length,0);
});
