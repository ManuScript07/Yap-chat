import crypto from 'node:crypto';

const clientCount = 100;
const audienceSize = 20;
const targetUserId = '00000000-0000-0000-0000-00000000b000';
const targetSessionId = '00000000-0000-0000-0000-00000000d000';
const apiUrl = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const anonKey = process.env.SUPABASE_ANON_KEY;
const jwtSecret = process.env.SUPABASE_JWT_SECRET;

if (!anonKey || !jwtSecret) {
  throw new Error(
    'Set SUPABASE_ANON_KEY and SUPABASE_JWT_SECRET from `supabase status -o json`.',
  );
}

const recipientUserIds = Array.from(
  {length: clientCount},
  (_, index) =>
    `00000000-0000-0000-0000-00000000c${String(index + 1).padStart(3, '0')}`,
);

const wait = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function signJwt(userId) {
  const encodedHeader = Buffer.from(
    JSON.stringify({alg: 'HS256', typ: 'JWT'}),
  ).toString('base64url');
  const encodedPayload = Buffer.from(
    JSON.stringify({
      aud: 'authenticated',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iss: 'supabase-demo',
      role: 'authenticated',
      sub: userId,
    }),
  ).toString('base64url');
  const signature = crypto
    .createHmac('sha256', jwtSecret)
    .update(`${encodedHeader}.${encodedPayload}`)
    .digest('base64url');
  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

class PhoenixClient {
  constructor({userId, topic, presence = false}) {
    this.userId = userId;
    this.topic = `realtime:${topic}`;
    this.presence = presence;
    this.ref = 0;
    this.messages = [];
    this.pendingReplies = new Map();
  }

  async connect() {
    const websocketUrl = apiUrl
      .replace(/^http/, 'ws')
      .concat(`/realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0`);
    this.socket = new WebSocket(websocketUrl);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WebSocket open timed out')), 5000);
      this.socket.addEventListener('open', () => {
        clearTimeout(timeout);
        resolve();
      }, {once: true});
      this.socket.addEventListener('error', () => {
        clearTimeout(timeout);
        reject(new Error('WebSocket open failed'));
      }, {once: true});
    });
    this.socket.addEventListener('message', (event) => this.#onMessage(event));
    await this.push('phx_join', {
      access_token: signJwt(this.userId),
      config: {
        broadcast: {ack: false, self: false},
        presence: {enabled: this.presence, key: this.presence ? this.userId : ''},
        private: true,
        postgres_changes: [],
      },
    });
  }

  async track(payload) {
    await this.push('presence', {
      event: 'track',
      payload,
      type: 'presence',
    });
  }

  clearMessages() {
    this.messages = [];
  }

  close() {
    this.socket?.close(1000, 'benchmark complete');
  }

  async push(event, payload) {
    const ref = String(++this.ref);
    const reply = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingReplies.delete(ref);
        reject(new Error(`Phoenix reply timed out for ${event}`));
      }, 5000);
      this.pendingReplies.set(ref, {resolve, reject, timeout});
    });
    this.socket.send(JSON.stringify({
      event,
      join_ref: null,
      payload,
      ref,
      topic: this.topic,
    }));
    return reply;
  }

  #onMessage(event) {
    const raw = String(event.data);
    const message = JSON.parse(raw);
    if (message.event === 'phx_reply' && this.pendingReplies.has(message.ref)) {
      const pending = this.pendingReplies.get(message.ref);
      this.pendingReplies.delete(message.ref);
      clearTimeout(pending.timeout);
      if (message.payload?.status === 'ok') pending.resolve(message.payload.response);
      else pending.reject(new Error(JSON.stringify(message.payload)));
      return;
    }
    this.messages.push({bytes: Buffer.byteLength(raw), message});
  }
}

async function rpc(userId, functionName, parameters) {
  const response = await fetch(`${apiUrl}/rest/v1/rpc/${functionName}`, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${signJwt(userId)}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(parameters),
  });
  if (!response.ok) throw new Error(`${functionName}: ${await response.text()}`);
}

function summarize(clients, predicate) {
  const deliveries = clients.flatMap((client) =>
    client.messages.filter(({message}) => predicate(message)),
  );
  return {
    bytes: deliveries.reduce((total, delivery) => total + delivery.bytes, 0),
    deliveries: deliveries.length,
  };
}

async function measureNewAudienceScopedBroadcast() {
  const clients = recipientUserIds.map((userId) => new PhoenixClient({
    userId,
    topic: `user:${userId}:chats`,
  }));
  try {
    await Promise.all(clients.map((client) => client.connect()));
    await wait(250);
    clients.forEach((client) => client.clearMessages());

    const onlineStartedAt = performance.now();
    await rpc(targetUserId, 'touch_my_presence_session', {
      target_session_id: targetSessionId,
    });
    await wait(500);
    const online = summarize(
      clients,
      (message) => message.event === 'broadcast' &&
          message.payload?.event === 'presence_changed' &&
          message.payload?.payload?.is_online === true,
    );

    const onlineElapsedMs = Number((performance.now() - onlineStartedAt).toFixed(1));
    clients.forEach((client) => client.clearMessages());
    const offlineStartedAt = performance.now();
    await rpc(targetUserId, 'close_my_presence_session', {
      target_session_id: targetSessionId,
    });
    await wait(500);
    const offline = summarize(
      clients,
      (message) => message.event === 'broadcast' &&
          message.payload?.event === 'presence_changed' &&
          message.payload?.payload?.is_online === false,
    );

    return {
      offline: {...offline, elapsedMs: Number((performance.now() - offlineStartedAt).toFixed(1))},
      online: {...online, elapsedMs: onlineElapsedMs},
    };
  } finally {
    clients.forEach((client) => client.close());
  }
}

async function measureFormerGlobalPresence() {
  const clients = recipientUserIds.map((userId) => new PhoenixClient({
    userId,
    topic: 'online',
    presence: true,
  }));
  try {
    await Promise.all(clients.map((client) => client.connect()));
    for (const client of clients) {
      await client.track({user_id: client.userId, version: 1});
    }
    await wait(500);
    clients.forEach((client) => client.clearMessages());

    const startedAt = performance.now();
    await clients[0].track({user_id: clients[0].userId, version: 2});
    await wait(500);
    const diff = summarize(
      clients,
      (message) => message.event === 'presence_diff',
    );
    return {
      elapsedMs: Number((performance.now() - startedAt).toFixed(1)),
      ...diff,
      // The previous Flutter client rebuilt presenceState() for every sync.
      clientStateEntriesRebuilt: diff.deliveries * clientCount,
    };
  } finally {
    clients.forEach((client) => client.close());
  }
}

const globalPresence = await measureFormerGlobalPresence();
await wait(250);
const audienceScoped = await measureNewAudienceScopedBroadcast();

console.log(JSON.stringify({
  audienceScoped,
  audienceSize,
  clientCount,
  globalPresence,
  note: 'Both measurements use the same local Realtime server and 100 authenticated WebSocket clients; only 20 are in the addressed audience.',
}, null, 2));
