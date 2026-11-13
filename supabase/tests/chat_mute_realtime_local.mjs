// Local Docker only; temporary random accounts are removed in finally.
// Local signing keys never leave memory and are never logged.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';

const url = 'http://127.0.0.1:54321';
function env(container) {
  const result = spawnSync('docker', ['inspect', '--format', '{{json .Config.Env}}', container], { encoding: 'utf8' });
  assert.equal(result.status, 0, 'Local Docker container unavailable');
  return Object.fromEntries(JSON.parse(result.stdout).map(value => {
    const index = value.indexOf('='); return [value.slice(0, index), value.slice(index + 1)];
  }));
}
const secret = env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anonKey = env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anonKey, 'Local signing configuration missing');
function token(user) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: user, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now()/1000)+300 })}`;
  return `${data}.${createHmac('sha256', secret).update(data).digest('base64url')}`;
}
function sql(input) {
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat', 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], {
    input: `set statement_timeout='15s';\n${input}`, encoding: 'utf8', timeout: 20000,
  });
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return result.stdout.trim();
}
async function setMuted(user, ids, muted) {
  const response = await fetch(`${url}/rest/v1/rpc/set_conversations_muted`, {
    method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${token(user)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ conversation_ids: ids, muted }), signal: AbortSignal.timeout(10000),
  });
  assert(response.ok, `set_conversations_muted HTTP ${response.status}: ${await response.text()}`);
}
const sockets = [];
async function connect(user, owner = user) {
  return await new Promise((resolve, reject) => {
    const ws = new WebSocket(`${url.replace('http', 'ws')}/realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0`);
    sockets.push(ws);
    const events = [];
    const timeout = setTimeout(() => { ws.close(); reject(Error('Realtime join timed out')); }, 10000);
    ws.addEventListener('open', () => ws.send(JSON.stringify({ topic: `realtime:user:${owner}:chats`, event: 'phx_join', ref: '1', payload: {
      config: { broadcast: { ack: false, self: false }, presence: { enabled: false }, postgres_changes: [], private: true }, access_token: token(user),
    } })));
    ws.addEventListener('error', () => { clearTimeout(timeout); reject(Error('Realtime transport failed')); });
    ws.addEventListener('message', ({data}) => {
      const event = JSON.parse(data);
      if (event.event === 'phx_reply' && event.ref === '1') {
        clearTimeout(timeout); resolve({ events, denied: event.payload.status !== 'ok' });
      }
      if (event.event === 'broadcast' && event.payload.payload?.reason === 'muted') {
        events.push({ payload: event.payload.payload, at: performance.now() });
      }
    });
  });
}
async function waitFor(predicate) {
  const deadline = Date.now()+10000;
  while (!predicate()) { assert(Date.now()<deadline, 'Realtime event missing'); await new Promise(resolve => setTimeout(resolve, 10)); }
}
const owner = randomUUID(), peer = randomUUID(), otherPeer = randomUUID(), stranger = randomUUID();
const chats = [randomUUID(), randomUUID()], messages = [randomUUID(), randomUUID()];
const pair = peerId => [owner, peerId].sort();
try {
  sql(`begin;
    insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
      ${[owner,peer,otherPeer,stranger].map(id=>`('${id}',false,false,'{}')`).join(',')};
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values
      ('${chats[0]}','${pair(peer)[0]}','${pair(peer)[1]}','${owner}'),
      ('${chats[1]}','${pair(otherPeer)[0]}','${pair(otherPeer)[1]}','${owner}');
    insert into public.conversation_members(conversation_id,user_id,is_muted) values
      ('${chats[0]}','${owner}',false),('${chats[0]}','${peer}',false),
      ('${chats[1]}','${owner}',true),('${chats[1]}','${otherPeer}',false);
    commit;`);
  const first = await connect(owner), second = await connect(owner), recipient = await connect(peer);
  assert(!first.denied && !second.denied && !recipient.denied);
  assert((await connect(stranger,owner)).denied, 'Another user read private mute settings');
  const started = performance.now();
  await setMuted(owner,chats,false);
  await waitFor(()=>first.events.length===1 && second.events.length===1);
  assert.deepEqual(first.events[0].payload.conversation_ids,[chats[1]]);
  assert.deepEqual(second.events[0].payload.conversation_ids,[chats[1]]);
  const delivery = [first.events[0].at-started,second.events[0].at-started].map(Math.round);
  await setMuted(owner,chats,false); // retry: no event and no inversion
  await Promise.all([setMuted(owner,chats,true),setMuted(owner,chats,true)]);
  await waitFor(()=>first.events.length>=2 && second.events.length>=2);
  assert.deepEqual(first.events[1].payload.conversation_ids,[...chats].sort());
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text)
    values('${messages[0]}','${chats[0]}','${peer}','text','muted local fixture');`);
  assert.equal(Number(sql(`select count(*) from public.push_notification_outbox where message_id='${messages[0]}' and recipient_user_id='${owner}';`)),0);
  await setMuted(owner,[chats[0]],false);
  await waitFor(()=>first.events.length>=3 && second.events.length>=3);
  sql(`insert into public.messages(id,conversation_id,sender_id,type,text)
    values('${messages[1]}','${chats[0]}','${peer}','text','unmuted local fixture');`);
  assert.equal(Number(sql(`select count(*) from public.push_notification_outbox where message_id='${messages[1]}' and recipient_user_id='${owner}';`)),1);
  await setMuted(stranger,[chats[0]],true); // no membership: cannot change owner
  await new Promise(resolve=>setTimeout(resolve,350));
  assert.equal(first.events.length,3); assert.equal(second.events.length,3);
  assert.equal(recipient.events.length,0);
  assert.equal(sql(`select is_muted from public.conversation_members where conversation_id='${chats[0]}' and user_id='${owner}';`),'f');
  console.log(JSON.stringify({ passed:true, owner_device_events:[3,3], peer_events:0, no_op_events:0,
    concurrent_same_state_events:1, foreign_channel_denied:true, owner_delivery_ms:delivery, muted_pushes:0, unmuted_pushes:1 }));
} finally {
  for (const ws of sockets) ws.close();
  sql(`begin; delete from public.conversations where id in('${chats[0]}','${chats[1]}');
    delete from public.profiles where id in('${owner}','${peer}','${otherPeer}','${stranger}');
    delete from auth.users where id in('${owner}','${peer}','${otherPeer}','${stranger}'); commit;`);
  assert.equal(Number(sql(`select count(*) from auth.users where id in('${owner}','${peer}','${otherPeer}','${stranger}');`)),0);
}
