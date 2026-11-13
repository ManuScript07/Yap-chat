// No Google requests or credentials. Exercises the production worker with an
// injected RPC/FCM transport; DB contracts have separate local integration tests.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createPushHandler, parseRetryAfter, withTimeout } from '../functions/push-message/worker.ts';

const id = 'b2000000-0000-0000-0000-000000000001';
const time = Date.parse('2026-10-11T12:00:00Z');
function fixture(options = {}) {
  const calls = [], sent = [], finishes = [];
  const job = {
    id, claim_token: 'lease', attempts: 1, expires_at: new Date(time + 3600_000).toISOString(),
    conversation_id: 'chat', message_id: 'message', friend_request_id: null,
    notification_type: 'chat_message', reaction_message_id: null, reaction_code: null,
    recipient_user_id: 'recipient', sender_id: 'sender', sender_name: 'Name',
    message_type: 'text', message_text: 'hello', message_created_at: new Date(time - 1000).toISOString(),
    ...options.job,
  };
  const devices = options.devices ?? [{ id: 'device1', token: 'token1' }];
  const deps = {
    secret: 'secret', configured: true, now: () => time, random: () => 0,
    createAdmin: () => ({ rpc: async (name, args) => {
      calls.push({ name, args });
      if (options.rpcError === name) return { data: null, error: { message: 'sensitive details' } };
      if (name === 'get_due_push_notification_ids') return { data: options.ids ?? [id], error: null };
      if (name === 'claim_push_notification') return { data: options.stopped ?? { job: { ...job, id: args.outbox_id }, devices }, error: null };
      finishes.push(args);
      return { data: { status: args.device_results.some(r => r.outcome === 'retry') ? 'pending' : 'sent' }, error: null };
    } }),
    authorize: async () => ({ projectId: 'project', accessToken: 'access' }),
    fetch: async (_url, init) => {
      sent.push(JSON.parse(init.body));
      assert.ok(init.signal instanceof AbortSignal);
      return options.delivery ? options.delivery(sent.length, init) : Response.json({ name: 'accepted' });
    },
    ...options.deps,
  };
  const handler = createPushHandler(deps);
  const invoke = (payload = { outbox_id: id }, headers = { 'x-webhook-secret': 'secret' }) => handler(new Request('https://local/push', {
    method: 'POST', headers, body: JSON.stringify(payload),
  }));
  return { handler, invoke, calls, sent, finishes };
}

test('auth, malformed payload, missing ID and method guards', async () => {
  const f = fixture();
  assert.equal((await f.invoke({}, {})).status, 401);
  assert.equal((await f.invoke(null)).status, 400);
  assert.equal((await f.invoke({ outbox_id: 'invalid' })).status, 400);
  assert.equal((await f.handler(new Request('https://local/push'))).status, 405);
  assert.equal((await f.handler(new Request('https://local/push', { method: 'POST', headers: { 'x-webhook-secret':'secret' }, body:'{' }))).status, 400);
  assert.equal(f.calls.length, 0);
});
test('normal data payload and remaining TTL, no notification or collapse change', async () => {
  const f = fixture();
  assert.equal((await f.invoke({ record: { id, attempts: 1000 } })).status, 200);
  const message = f.sent[0].message;
  assert.equal(message.android.ttl, '3600s');
  assert.equal(message.notification, undefined);
  assert.equal(message.android.collapse_key, undefined);
  assert.equal(message.data.message_id, 'message');
  assert.equal(message.data.content_type, 'text');
  assert.deepEqual(f.calls[0].args, { outbox_id: id });
  assert.equal(f.finishes[0].device_results[0].outcome, 'accepted');
});
for (const status of ['expired','no_devices','message_deleted','already_processed','failed']) {
  test(`database stopped job ${status} makes no FCM/auth call`, async () => {
    const f = fixture({ stopped: { status }, deps: { authorize: async () => { throw Error('must not authorize'); } } });
    assert.deepEqual(await (await f.invoke()).json(), { status });
    assert.equal(f.sent.length, 0);
    assert.equal(f.finishes.length, 0);
  });
}
test('fetch throw persists retry rather than leaving processing forever', async () => {
  const f = fixture({ delivery: () => { throw Error('network'); } });
  assert.equal((await f.invoke()).status, 200);
  assert.equal(f.finishes[0].device_results[0].outcome, 'retry');
  assert.equal(f.finishes[0].retry_delay_seconds, 60);
});
for (const status of [429,500,503,401]) {
  test(`FCM ${status} honors Retry-After, only one send per attempt`, async () => {
    const f = fixture({ delivery: () => Response.json({ error: { status: 'TEMPORARY' } }, { status, headers: { 'Retry-After': '300' } }) });
    await f.invoke();
    assert.equal(f.sent.length, 1);
    assert.equal(f.finishes[0].retry_delay_seconds, 300);
    assert.equal(f.finishes[0].device_results[0].outcome, 'retry');
  });
}
for (const code of ['UNREGISTERED','SENDER_ID_MISMATCH']) {
  test(`confirmed invalid token ${code}`, async () => {
    const f = fixture({ delivery: () => Response.json({ error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: code }] } }, { status: 404 }) });
    await f.invoke();
    assert.equal(f.finishes[0].device_results[0].outcome, 'invalid');
    assert.equal(f.sent.length, 1);
  });
}
for (const status of [400,403,404]) {
  test(`generic permanent ${status} does not disable token or loop retries`, async () => {
    const f = fixture({ delivery: () => Response.json({ error: { status: 'CONFIGURATION_ERROR' } }, { status }) });
    await f.invoke();
    assert.equal(f.finishes[0].device_results[0].outcome, 'failed');
    assert.equal(f.sent.length, 1);
  });
}
test('partial delivery saves both outcomes', async () => {
  const f = fixture({ devices: [{id:'one',token:'one'},{id:'two',token:'two'}],
    delivery: count => count === 1 ? Response.json({}) : Response.json({}, {status:503}) });
  await f.invoke();
  assert.deepEqual(f.finishes[0].device_results.map(r => r.outcome), ['accepted','retry']);
});
test('401 invalidates rejected OAuth token before the scheduled retry', async () => {
  let rejected;
  const f = fixture({ deps: { invalidateAuthorization: token => { rejected = token; } },
    delivery: () => Response.json({}, {status:401}) });
  await f.invoke();
  assert.equal(rejected,'access');
  assert.equal(f.finishes[0].device_results[0].outcome,'retry');
});
test('auth failure persists retry', async () => {
  const f = fixture({ deps: { authorize: async () => { throw Error('oauth'); } } });
  await f.invoke();
  assert.equal(f.sent.length, 0);
  assert.equal(f.finishes[0].device_results[0].outcome, 'retry');
});
test('DB failures are non-success and never expose sensitive details', async () => {
  for (const rpcError of ['claim_push_notification','finish_push_notification']) {
    const f = fixture({ rpcError });
    const response = await f.invoke();
    assert.equal(response.status, 500);
    assert.deepEqual(await response.json(), { error:'worker_failed' });
  }
});
test('reaction and friend request navigation keys preserved', async () => {
  for (const type of ['message_reaction','friend_request']) {
    const f = fixture({ job: { notification_type:type, reaction_message_id:'reaction-message', friend_request_id:'request' } });
    await f.invoke();
    assert.equal(f.sent[0].message.data.notification_type, type);
    assert.equal(f.sent[0].message.data.message_id, 'reaction-message');
    assert.equal(f.sent[0].message.data.friend_request_id, 'request');
  }
});
test('expiry during OAuth makes no FCM send', async () => {
  const f = fixture({ job: {expires_at:new Date(time-1).toISOString()} });
  await f.invoke();
  assert.equal(f.sent.length, 0);
});
test('scheduled batch is bounded to four concurrent jobs', async () => {
  let active = 0, maxActive = 0;
  const f = fixture({ ids:Array.from({length:20},(_,i)=>`job${i}`), delivery:async () => {
    active++; maxActive = Math.max(maxActive, active);
    await new Promise(resolve=>setTimeout(resolve,2));
    active--; return Response.json({});
  } });
  const response = await f.invoke({retry_due:true});
  assert.equal((await response.json()).processed,20);
  assert.equal(f.sent.length,20);
  assert.ok(maxActive<=4);
  assert.deepEqual(f.calls[0].args,{batch_size:20});
});
test('Retry-After dates and timeout guard', async () => {
  assert.equal(parseRetryAfter(new Date(time+90_000).toUTCString(),time),90);
  assert.equal(parseRetryAfter('bad',time),0);
  assert.equal(parseRetryAfter('-1',time),0);
  await assert.rejects(withTimeout(new Promise(()=>{}),5),/operation_timeout/);
  assert.equal(await withTimeout(Promise.resolve('ok'),100), 'ok');
});
