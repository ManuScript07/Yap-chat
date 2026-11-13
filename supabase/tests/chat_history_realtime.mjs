// Real local WebSocket + RPC contract; never reads production configuration.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';

const base = 'http://127.0.0.1:54321';
function env(container) {
  const r = spawnSync('docker', ['inspect', '--format', '{{json .Config.Env}}', container], { encoding: 'utf8' });
  assert.equal(r.status, 0, 'Local container unavailable');
  return Object.fromEntries(JSON.parse(r.stdout).map(v => {
    const i = v.indexOf('='); return [v.slice(0, i), v.slice(i + 1)];
  }));
}
const secret = env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anon = env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anon);
function token(user) {
  const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const value = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: user,
    role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 300 });
  return value + '.' + createHmac('sha256', secret).update(value).digest('base64url');
}
function sql(input) {
  const r = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat', 'psql', '-U', 'postgres',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], { input, encoding: 'utf8', timeout: 30000 });
  assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
}
async function rpc(user, name, params) {
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, { method: 'POST',
    headers: { apikey: anon, Authorization: `Bearer ${token(user)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(params), signal: AbortSignal.timeout(10000) });
  const raw = await response.text();
  const data = raw ? JSON.parse(raw) : null;
  assert(response.ok, `${name}: ${JSON.stringify(data)}`); return data;
}
const sockets = [];
async function connect(user) {
  const ws = new WebSocket(base.replace('http', 'ws') + `/realtime/v1/websocket?apikey=${encodeURIComponent(anon)}&vsn=1.0.0`);
  sockets.push(ws);
  const events = [];
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { ws.close(); reject(Error('Local realtime join timed out')); }, 10000);
    ws.addEventListener('error', () => { clearTimeout(timer); reject(Error('Local websocket error')); });
    ws.addEventListener('open', () => ws.send(JSON.stringify({ topic: `realtime:user:${user}:chats`,
      event: 'phx_join', ref: '1', payload: { config: { broadcast: { ack: false, self: false },
        presence: { enabled: false }, postgres_changes: [], private: true }, access_token: token(user) } })));
    ws.addEventListener('message', ({ data }) => {
      const message = JSON.parse(data);
      if (message.event === 'phx_reply' && message.ref === '1') {
        clearTimeout(timer);
        if (message.payload.status !== 'ok') reject(Error('Member join rejected')); else resolve();
      }
      if (message.event === 'broadcast') events.push({ at: performance.now(), payload: message.payload.payload });
    });
  });
  return { ws, events };
}
async function waitFor(channel, predicate) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    const event = channel.events.find(e => predicate(e.payload));
    if (event) return event;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw Error('Expected local realtime event not received');
}
async function waitForCount(channel, predicate, expected) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (channel.events.filter(e => predicate(e.payload)).length >= expected) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw Error(`Expected ${expected} local realtime events not received`);
}
const [a, b] = [randomUUID(), randomUUID()].sort();
const chat = randomUUID();
let report;
try {
  sql(`begin; insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
    values('${a}',false,false,'{}'),('${b}',false,false,'{}');
    insert into public.conversations(id,user_one_id,user_two_id,created_by) values('${chat}','${a}','${b}','${a}');
    insert into public.conversation_members(conversation_id,user_id) values('${chat}','${a}'),('${chat}','${b}');
    set local session_replication_role=replica;
    insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
    select md5('${chat}:'||i)::uuid,'${chat}','${a}','text','local history '||i,
      statement_timestamp()-interval '1 hour'+i*interval '1 second' from generate_series(1,150)i;
    set local session_replication_role=origin;
    do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
      perform private.rebuild_chat_unread_projection(array['${chat}']::uuid[]);end if;end $f$;commit;`);
  const target = sql(`select md5('${chat}:20')::uuid;`);
  const personal = sql(`select md5('${chat}:21')::uuid;`);
  // Independent sockets model two signed-in devices of the author.
  const first = await connect(a), otherAuthorDevice = await connect(a), second = await connect(b);
  const window = await rpc(b, 'get_conversation_message_window', { target_conversation_id: chat, target_message_id: target });
  assert(window.some(m => m.id === target));
  const head = await rpc(b, 'get_conversation_messages', { target_conversation_id: chat, page_size: 60 });
  assert(!head.some(m => m.id === target), 'Target must be outside the live head');
  const start = performance.now();
  await rpc(a, 'soft_delete_message', { target_message_id: target, delete_for_everyone: true });
  const matches = payload => payload.reason === 'deleted' && payload.message_id === target;
  const [ownEvent, peerEvent] = await Promise.all([
    waitFor(first, matches), waitFor(second, matches), waitFor(otherAuthorDevice, matches),
  ]);
  assert.deepEqual(await rpc(b, 'get_conversation_message_window', { target_conversation_id: chat, target_message_id: target }), []);
  await new Promise(resolve => setTimeout(resolve, 150));
  const initialCounts = [first, otherAuthorDevice, second].map(c => c.events.filter(e => matches(e.payload)).length);
  assert.deepEqual(initialCounts, [1, 1, 1], 'One global delete must notify each device once');

  // A network retry and two concurrent retries still identify the tombstone.
  // This does not promise exactly-once network delivery: these are four actual
  // UPDATEs, each with a single database producer.
  await rpc(a, 'soft_delete_message', { target_message_id: target, delete_for_everyone: true });
  await Promise.all([
    rpc(a, 'soft_delete_message', { target_message_id: target, delete_for_everyone: true }),
    rpc(a, 'soft_delete_message', { target_message_id: target, delete_for_everyone: true }),
  ]);
  await Promise.all([first, otherAuthorDevice, second].map(c => waitForCount(c, matches, 4)));
  await rpc(b, 'soft_delete_message', { target_message_id: personal, delete_for_everyone: false });
  await waitFor(second, p => p.reason === 'deleted' && p.message_id === personal);
  await new Promise(resolve => setTimeout(resolve, 100));
  assert(!first.events.some(e => e.payload.message_id === personal), 'Personal hide leaked to peer');
  assert(!otherAuthorDevice.events.some(e => e.payload.message_id === personal), 'Personal hide leaked to peer device');
  assert((await rpc(a, 'get_conversation_message_window', { target_conversation_id: chat, target_message_id: personal })).some(m => m.id === personal));

  const ownHidden = sql(`select md5('${chat}:22')::uuid;`);
  await rpc(a, 'soft_delete_message', { target_message_id: ownHidden, delete_for_everyone: false });
  await Promise.all([first, otherAuthorDevice].map(c => waitFor(c,
    p => p.reason === 'deleted' && p.message_id === ownHidden)));
  assert((await rpc(b, 'get_conversation_message_window', { target_conversation_id: chat, target_message_id: ownHidden })).some(m => m.id === ownHidden));

  const nonAuthorHidden = sql(`select md5('${chat}:23')::uuid;`);
  await rpc(b, 'soft_delete_message', { target_message_id: nonAuthorHidden, delete_for_everyone: true });
  await waitFor(second, p => p.reason === 'deleted' && p.message_id === nonAuthorHidden);
  assert((await rpc(a, 'get_conversation_message_window', { target_conversation_id: chat, target_message_id: nonAuthorHidden })).some(m => m.id === nonAuthorHidden));

  second.ws.close();
  const missedDeletion = sql(`select md5('${chat}:24')::uuid;`);
  await rpc(a, 'soft_delete_message', { target_message_id: missedDeletion, delete_for_everyone: true });
  const missed = randomUUID();
  await rpc(a, 'send_chat_message', { message_id: missed, target_conversation_id: chat,
    message_type: 'text', message_text: 'sent while receiver disconnected' });
  const reconnected = await connect(b);
  const recovered = await rpc(b, 'get_conversation_messages', { target_conversation_id: chat, page_size: 60 });
  assert(recovered.some(m => m.id === missed));
  assert.deepEqual(await rpc(b, 'get_conversation_message_window', {
    target_conversation_id: chat, target_message_id: missedDeletion,
  }), [], 'Missed deletion must be recoverable from server state after rejoin');
  const next = randomUUID();
  await rpc(a, 'send_chat_message', { message_id: next, target_conversation_id: chat,
    message_type: 'text', message_text: 'delivery after reconnect' });
  await waitFor(reconnected, p => p.reason === 'insert' && p.conversation_id === chat);
  await rpc(b, 'mark_visible_conversation_messages_read', { target_conversation_id: chat, visible_message_ids: [next] });
  await waitFor(first, p => p.reason === 'read' && p.conversation_id === chat);
  assert.equal(Number(sql(`select count(*) from public.message_receipts where user_id='${b}' and message_id='${next}';`)), 1);
  assert.equal(Number(sql(`select count(*) from public.message_receipts where user_id='${b}' and message_id='${missed}';`)), 0);
  for (const channel of [first, otherAuthorDevice, second]) {
    assert.equal(channel.events.filter(e => matches(e.payload)).length, 4);
  }
  for (const channel of [first, otherAuthorDevice]) {
    assert.equal(channel.events.filter(e => e.payload.message_id === ownHidden).length, 1);
    assert(!channel.events.some(e => e.payload.message_id === nonAuthorHidden), 'Non-author fallback leaked to peer');
  }
  assert(!second.events.some(e => e.payload.message_id === ownHidden), 'Own hide leaked to peer');
  assert.equal(second.events.filter(e => e.payload.message_id === personal).length, 1);
  assert.equal(second.events.filter(e => e.payload.message_id === nonAuthorHidden).length, 1);
  report = { passed: true, deep_deletion_events_per_device: initialCounts,
    duplicate_author_deletion_event: false, retries_and_concurrent_calls_per_device: [4, 4, 4],
    personal_hide_isolated: true, personal_hide_reaches_all_author_devices: true,
    non_author_global_flag_remains_personal: true, missed_deletion_recovered_after_rejoin: true,
    sender_deletion_ms: +(ownEvent.at - start).toFixed(2), peer_deletion_ms: +(peerEvent.at - start).toFixed(2),
    disconnected_message_recovered_by_head_rpc: true, delivery_after_rejoin: true, only_selected_message_read: true };
} finally {
  for (const ws of sockets) ws.close();
  sql(`begin; delete from public.conversations where id='${chat}';
    delete from public.profiles where id in ('${a}','${b}');
    delete from auth.users where id in ('${a}','${b}'); commit;`);
}
mkdirSync('.dart_tool/chat_history_validation', { recursive: true });
writeFileSync('.dart_tool/chat_history_validation/realtime_history.json', JSON.stringify(report, null, 2));
console.log(JSON.stringify(report));
