import {spawnSync} from 'node:child_process';
import {randomBytes, randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, renameSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const marker = 'yap-pagination-lab-v1';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function literal(value) { return `'${String(value).replaceAll("'", "''")}'`; }
const ids = values => values.map(v => { if (!uuid.test(v)) throw Error('Invalid fixture UUID'); return literal(v); }).join(',');
export function localUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(url.hostname) || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw Error('The pagination lab accepts loopback HTTP URLs only');
  }
  return url.origin;
}
function command(exe, args, options = {}) {
  const result = spawnSync(exe, args, {cwd: root, encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024, ...options});
  if (result.status !== 0) throw Error(`Local command failed: ${exe}: ${(result.stderr || result.error?.message || '').slice(0, 500)}`);
  return result.stdout.trim();
}
export class PaginationLab {
  constructor(name = 'manual') {
    if (!/^[a-z0-9-]{1,32}$/.test(name)) throw Error('Invalid local lab name');
    this.directory = join(root, '.local', 'pagination-lab', name);
    this.statePath = join(this.directory, 'state.json');
    this.state = existsSync(this.statePath) ? JSON.parse(readFileSync(this.statePath, 'utf8')) : null;
    const config = readFileSync(join(root, 'supabase', 'config.toml'), 'utf8');
    this.project = config.match(/^project_id\s*=\s*"([a-zA-Z0-9_-]+)"/m)?.[1];
    if (!this.project) throw Error('Local Supabase project ID not found');
    this.container = `supabase_db_${this.project}`;
    this.sessions = new Map();
  }
  connect() {
    const labels = JSON.parse(command('docker', ['inspect', this.container, '--format', '{{json .Config.Labels}}']));
    if (labels['com.supabase.cli.project'] !== this.project || resolve(labels['com.supabase.cli.workdir'] || '').toLowerCase() !== root.toLowerCase()) {
      throw Error('Docker database does not belong to this workspace');
    }
    const cliPackage = JSON.parse(readFileSync(join(root,'node_modules','supabase','package.json'),'utf8'));
    const cli = join(root,'node_modules','supabase',typeof cliPackage.bin==='string'?cliPackage.bin:cliPackage.bin.supabase);
    const status = JSON.parse(command(process.execPath,[cli,'status','-o','json']));
    this.api = localUrl(status.API_URL);
    const configuredPort = Number(readFileSync(join(root, 'supabase', 'config.toml'), 'utf8').match(/\[api\][\s\S]*?^port\s*=\s*(\d+)/m)?.[1]);
    if (new URL(this.api).port !== String(configuredPort)) throw Error('Local API port does not match this workspace');
    this.key = status.ANON_KEY;
    this.clientKey = status.PUBLISHABLE_KEY || this.key;
    this.adminKey = status.SERVICE_ROLE_KEY;
    if (!this.key || !this.adminKey) throw Error('Local public/admin API keys unavailable');
    if (this.state && (this.state.marker !== marker || this.state.api !== this.api || this.state.project !== this.project)) {
      throw Error('Fixture manifest does not match the local project');
    }
    if (this.state && (!/^[a-f0-9]{12}$/.test(this.state.run) || !Array.isArray(this.state.users) ||
        !this.state.users.every(u=>uuid.test(u.id)&&Number.isInteger(u.index)&&u.email?.endsWith('@example.test')) ||
        (this.state.seeded && (!this.state.users.some(u=>u.id===this.state.owner?.id&&u.index===0) ||
          !this.state.users.some(u=>u.id===this.state.hub?.id&&u.index===1))))) {
      throw Error('Invalid local fixture manifest');
    }
    return this;
  }
  sql(query) {
    if (!this.api) throw Error('Connect to the verified local project first');
    return command('docker', ['exec', '-i', this.container, 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], {
      input: `set statement_timeout='45s';\n${query}`,
    });
  }
  data(query) { const result = this.sql(query); return result ? JSON.parse(result.split('\n').at(-1)) : null; }
  save() {
    mkdirSync(this.directory, {recursive: true});
    const temp = `${this.statePath}.tmp`;
    writeFileSync(temp, JSON.stringify(this.state, null, 2), {mode: 0o600});
    renameSync(temp, this.statePath);
  }
  async request(path, {token = this.adminKey, method = 'GET', body, bytes, contentType = 'application/json'} = {}) {
    const response = await fetch(`${this.api}${path}`, {
      method, headers: {apikey: this.key, Authorization: `Bearer ${token}`, 'Content-Type': contentType},
      body: bytes ?? (body === undefined ? undefined : JSON.stringify(body)), signal: AbortSignal.timeout(30000),
    });
    const text = await response.text();
    let data; try { data = text ? JSON.parse(text) : null; } catch { data = null; }
    if (!response.ok) throw Error(`Local API ${path.split('?')[0]}: ${response.status} ${String(data?.msg || data?.message || data?.error_description || data?.error || 'request failed').slice(0, 220)}`);
    return data;
  }
  async session(user) {
    if (!user) throw Error('Actor is outside this fixture');
    const cached = this.sessions.get(user.id);
    if (cached && cached.expires_at > Date.now()/1000+60) return cached;
    const session = await this.request('/auth/v1/token?grant_type=password', {method: 'POST', token: this.key,
      body: {email: user.email, password: this.state.password}});
    if (session.user?.id !== user.id) throw Error('Unexpected test account in GoTrue session');
    this.sessions.set(user.id,session);
    return session;
  }
  async rpc(user, name, params = {}, session) {
    const auth = session || await this.session(user);
    return this.request(`/rest/v1/rpc/${name}`, {method: 'POST', token: auth.access_token, body: params});
  }
  requireSeed() {
    if (!this.state?.seeded) throw Error('Run seed first');
  }
  async seed({peers = 360} = {}) {
    if (!Number.isInteger(peers) || peers < 300 || peers > 1000) throw Error('Use 300–1000 peers');
    if (this.state?.seeded) return this.status();
    if (this.state?.users?.length) throw Error('Interrupted seed found: run cleanup before seeding again');
    this.state = {marker, project: this.project, api: this.api, run: randomBytes(6).toString('hex'), password: randomBytes(32).toString('base64url'),
      users: [], chats: [], createdAt: new Date().toISOString(), seeded: false};
    this.save();
    const create = async index => {
      const email = `pagination-${this.state.run}-${index}@example.test`;
      const response = await this.request('/auth/v1/admin/users', {method: 'POST', body: {
        email, password: this.state.password, email_confirm: true,
        user_metadata: {name: `Лаб ${String(index).padStart(3, '0')}`, pagination_lab: marker, pagination_run: this.state.run},
      }});
      const user = response.user || response;
      if (!uuid.test(user.id)) throw Error('Auth admin did not return a user ID');
      this.state.users.push({id: user.id, email, index});
      this.save();
    };
    for (let offset = 0; offset < peers + 2; offset += 6) {
      await Promise.all(Array.from({length: Math.min(6, peers + 2 - offset)}, (_, i) => create(offset + i)));
    }
    this.state.users.sort((a,b) => a.index - b.index);
    this.state.owner = this.state.users[0];
    this.state.hub = this.state.users[1];
    const people = this.state.users.slice(2);
    this.state.chats = people.slice(0,220).map(peer => ({id: randomUUID(), peerId: peer.id}));
    this.save();
    const profileValues = this.state.users.map(user => {
      const n = user.index - 2;
      let name = `Лаб ${String(user.index).padStart(3,'0')} • ${['Александр','Мария','Дмитрий','Анна','Никита','Екатерина'][user.index % 6]}`;
      let username = `lab_${this.state.run}_${String(user.index).padStart(3,'0')}`;
      if (n >= 0 && n % 9 === 0) name = 'Одинаковое имя Лаб';
      if (user.index === 0) { name = 'Мой тестовый аккаунт'; username = `lab_owner_${this.state.run}`; }
      if (user.index === 1) { name = 'Друзья тестового профиля'; username = `lab_hub_${this.state.run}`; }
      if (n === 158) name = 'Дальний друг Лаб';
      if (n === 219) name = 'Глубокий чат Лаб';
      if (n === 239) name = 'Последний друг профиля Лаб';
      return `(${literal(user.id)}::uuid,${literal(name)},${literal(username)},${literal(user.index % 2 ? 'female' : 'male')})`;
    }).join(',');
    const owner = this.state.owner.id, hub = this.state.hub.id;
    const friendship = (a,b,index) => `(least('${a}'::uuid,'${b}'::uuid),greatest('${a}'::uuid,'${b}'::uuid),statement_timestamp()-interval '1 day'-${Math.floor(index/4)}*interval '1 minute')`;
    const friendships = [friendship(owner,hub,0), ...people.slice(0,159).map((p,i) => friendship(owner,p.id,i+1)),
      ...people.slice(0,240).map((p,i) => friendship(hub,p.id,i+1))];
    const requests = [
      ...people.slice(160,220).map((p,i) => `('${p.id}','${owner}',statement_timestamp()-${Math.floor(i/4)}*interval '1 minute')`),
      ...people.slice(220,280).map((p,i) => `('${owner}','${p.id}',statement_timestamp()-${Math.floor(i/4)}*interval '1 minute')`),
    ];
    this.sql(`begin;
      update public.profiles p set display_name=v.name,username=v.username,gender=v.gender,
        onboarding_completed=true,birth_date=date '1990-01-01'+(get_byte(uuid_send(p.id),0)%14)*365,
        terms_accepted_at=statement_timestamp(),privacy_accepted_at=statement_timestamp(),terms_version='v1',privacy_policy_version='v1',
        last_seen_at=statement_timestamp(),bio='Локальный набор для проверки списков',show_friends_count=true
      from (values ${profileValues}) as v(id,name,username,gender) where p.id=v.id;
      insert into public.friendships(user_one_id,user_two_id,created_at) values ${friendships.join(',')};
      insert into public.friend_requests(sender_id,recipient_id,created_at) values ${requests.join(',')};
      insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values ${this.state.chats.map((chat,i) => `('${chat.id}',least('${owner}'::uuid,'${chat.peerId}'::uuid),greatest('${owner}'::uuid,'${chat.peerId}'::uuid),'${i<20 ? owner : chat.peerId}',statement_timestamp()-interval '2 days')`).join(',')};
      insert into public.conversation_members(conversation_id,user_id,is_muted) values ${this.state.chats.flatMap((chat,i) => [`('${chat.id}','${owner}',${i%5===0})`,`('${chat.id}','${chat.peerId}',false)`]).join(',')};
      insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values ${this.state.chats.map((chat,i) => `('${randomUUID()}','${chat.id}','${chat.peerId}','text',${literal(`Тестовое превью ${String(i+1).padStart(3,'0')}`)},statement_timestamp()-interval '1 day'-${Math.floor(i/4)}*interval '1 minute')`).join(',')};
      insert into public.message_receipts(message_id,user_id,read_at) select m.id,'${owner}',statement_timestamp() from public.messages m
        where m.conversation_id in (${ids(this.state.chats.filter((_,i)=>i%3!==0).map(c=>c.id))});
      commit;`);
    // Private bucket uploads use the real Storage API. No public external URLs.
    for (let offset = 0; offset < this.state.users.length; offset += 8) {
      await Promise.all(this.state.users.slice(offset,offset+8).filter(u=>u.index%4!==0).map(async user => {
        const path = `${user.id}/pagination-${this.state.run}.jpg`;
        const bytes = readFileSync(join(root,'tools','pagination_lab','avatars',`${user.index%12}.jpg`));
        await this.request(`/storage/v1/object/avatars/${path}`, {method:'POST', bytes, contentType:'image/jpeg'});
        this.sql(`insert into public.profile_photos(profile_id,position,storage_path) values ('${user.id}',0,${literal(path)});
          update public.profiles set avatar_storage_path=${literal(path)},avatar_updated_at=statement_timestamp(),yandex_avatar_disabled=true where id='${user.id}';`);
      }));
    }
    this.state.seeded = true;
    this.save();
    await this.refreshNearby();
    return this.status();
  }
  async refreshNearby() {
    this.requireSeed();
    const owner = this.state.owner.id;
    const anchor = this.data(`select coalesce((select jsonb_build_object('lat',latitude,'lon',longitude) from public.user_locations where user_id='${owner}'),'{"lat":55.75,"lon":37.61}'::jsonb);`);
    const users = this.state.users;
    this.sql(`begin; update public.profiles set last_seen_at=statement_timestamp() where id in (${ids(users.map(u=>u.id))});
      insert into public.user_locations(user_id,latitude,longitude,updated_at) values ${users.map(u=>{
        const distance = u.index >= users.length-20 ? 5 : Math.floor(u.index/4)*.00004;
        return `('${u.id}',${Math.max(-89,Math.min(89,anchor.lat+distance))},${Math.max(-179,Math.min(179,anchor.lon+distance))},statement_timestamp())`;
      }).join(',')} on conflict(user_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,updated_at=excluded.updated_at;
      commit;`);
    return {anchor, nearbyLimit:100, message:'Координаты привязаны к текущему положению тестового аккаунта'};
  }
  status() {
    if (!this.state?.seeded) return {seeded:false};
    const owner = this.state.owner.id;
    const counts = this.data(`select jsonb_build_object(
      'profiles',(select count(*) from auth.users where raw_user_meta_data->>'pagination_run'=${literal(this.state.run)}),
      'chats',(select count(*) from public.conversation_members where user_id='${owner}' and hidden_at is null),
      'friends',(select count(*) from public.friendships where '${owner}' in (user_one_id,user_two_id)),
      'incoming',(select count(*) from public.friend_requests where recipient_id='${owner}'),
      'outgoing',(select count(*) from public.friend_requests where sender_id='${owner}'),
      'profileFriends',(select count(*) from public.friendships where '${this.state.hub.id}' in (user_one_id,user_two_id)));`);
    const cachePath=join(this.directory,'cache-verification.json');
    const cache=existsSync(cachePath)?JSON.parse(readFileSync(cachePath,'utf8')):null;
    return {seeded:true, run:this.state.run, api:this.api, ...counts, owner:owner, hubUsername:`lab_hub_${this.state.run}`,
      cacheCheck:cache?.owner===owner?{friends:cache.friendsCached,friendPaginationIssue:cache.friendPaginationIssue,offline:cache.offlineAfterDatabaseReopen}:null,
      searches:['Глубокий чат Лаб','Дальний друг Лаб','Последний друг профиля Лаб','Одинаковое имя Лаб']};
  }
  async prepare() {
    this.requireSeed();
    const session = await this.session(this.state.owner);
    const path = join(this.directory,'launch.json');
    writeFileSync(path,JSON.stringify({PAGINATION_LAB_URL:this.api,PAGINATION_LAB_KEY:this.clientKey,
      PAGINATION_LAB_OWNER_ID:this.state.owner.id,PAGINATION_LAB_REFRESH_TOKEN:session.refresh_token},null,2),{mode:0o600});
    return {file:path, owner:this.state.owner.id};
  }
  async verify() {
    this.requireSeed();
    const owner=this.state.owner, auth=await this.session(owner), report={};
    const seenChats=new Set();let cursor=null,pages=0;
    do {
      const page=await this.rpc(owner,'get_chat_list_page',{page_size:50,search_query:'',
        after_activity_at:cursor?.activity_at??null,after_conversation_id:cursor?.conversation_id??null},auth);
      assert(page.items.length<=50);
      for(const row of page.items){assert(!seenChats.has(row.id),'duplicate chat across cursor pages');seenChats.add(row.id);}
      pages++;assert(pages<40);cursor=page.next_cursor;assert.equal(page.has_more,cursor!==null);
    }while(cursor);
    assert.equal(seenChats.size,this.status().chats);
    report.chats={pages,total:seenChats.size};
    const search=await this.rpc(owner,'get_chat_list_page',{search_query:'глубокий чат лаб',page_size:50},auth);
    assert(search.items.some(row=>row.peer_id===this.state.users[221]?.id || row.id===this.state.chats[219].id),'deep chat search missed its target');
    const seenFriends=new Set();let after=null;pages=0;
    do {
      const rows=await this.rpc(owner,'get_friends_page',{page_size:50,after_friends_since:after?.friends_since??null,after_friend_id:after?.id??null},auth);
      assert(rows.length<=50);
      for(const row of rows){assert(!seenFriends.has(row.id),'duplicate friend across cursor pages');seenFriends.add(row.id);}
      pages++;assert(pages<40);after=rows.length&&rows[0].has_more?rows.at(-1):null;
    }while(after);
    assert.equal(seenFriends.size,this.status().friends);
    report.friends={pages,total:seenFriends.size};
    const candidates=await this.rpc(owner,'search_friend_candidates',{search_query:'Дальний друг Лаб',result_limit:10},auth);
    assert(candidates.some(row=>row.id===this.state.users[160].id),'deep friend search missed its target');
    const requests=await this.rpc(owner,'get_friend_requests',{},auth);
    assert.equal(requests.filter(r=>r.direction==='incoming').length,this.status().incoming);
    assert.equal(requests.filter(r=>r.direction==='outgoing').length,this.status().outgoing);
    report.requests={incoming:this.status().incoming,outgoing:this.status().outgoing,paginated:false};
    const profileFriends=new Set();after=null;pages=0;
    do {
      const rows=await this.rpc(owner,'get_user_profile_friends',{target_user_id:this.state.hub.id,page_size:30,
        after_display_name:after?.display_name??null,after_user_id:after?.id??null},auth);
      assert(rows.length<=30);
      for(const row of rows){assert(!profileFriends.has(row.id),'duplicate profile friend across cursor pages');profileFriends.add(row.id);}
      pages++;assert(pages<40);after=rows.length&&rows[0].has_more?rows.at(-1):null;
    }while(after);
    assert(profileFriends.size>=240);
    assert(profileFriends.has(this.state.users[241].id),'last profile friend was not paginated');
    report.profileFriends={pages,total:profileFriends.size};
    await this.refreshNearby();
    const nearby=new Set();after=null;pages=0;
    do {
      const rows=await this.rpc(owner,'get_nearby_people',{page_size:30,after_user_id:after},auth);
      assert(rows.length<=30);
      for(const row of rows){assert(!nearby.has(row.id),'duplicate nearby person across cursor pages');nearby.add(row.id);}
      pages++;assert(pages<10);after=rows.length&&rows[0].has_more?rows.at(-1).id:null;
    }while(after);
    assert.equal(nearby.size,100);
    report.nearby={pages,total:nearby.size,serverLimit:100};
    report.searchTargetsFound=true;
    report.realGoTrueSessions=true;
    writeFileSync(join(this.directory,'verification.json'),JSON.stringify(report,null,2));
    return report;
  }
  async action(name) {
    this.requireSeed();
    const owner = this.state.owner, people = this.state.users.slice(2);
    const user = id => this.state.users.find(u=>u.id===id);
    if (name==='nearby-refresh') return this.refreshNearby();
    if (name==='old-chat-message') {
      const row=this.data(`select jsonb_build_object('id',c.conversation_id,'peer',case when d.user_one_id='${owner.id}' then d.user_two_id else d.user_one_id end)
        from private.chat_list_catalog c join public.conversations d on d.id=c.conversation_id
        where c.user_id='${owner.id}' and c.is_visible and d.user_one_id in (${ids(this.state.users.map(u=>u.id))}) and d.user_two_id in (${ids(this.state.users.map(u=>u.id))}) order by c.activity_at,c.conversation_id limit 1;`);
      if (!row) throw Error('No visible fixture chats remain');
      await this.rpc(user(row.peer),'send_chat_message',{message_id:randomUUID(),target_conversation_id:row.id,message_type:'text',message_text:`Новое сообщение в старом чате ${new Date().toLocaleTimeString('ru-RU')}`});
      return {message:'Самый старый чат получил новое сообщение',chatId:row.id};
    }
    if (name==='new-chat') {
      const peerId=this.data(`select to_jsonb(p.id) from public.profiles p where p.id in (${ids(people.map(p=>p.id))}) and not exists(select 1 from public.conversations c where '${owner.id}' in(c.user_one_id,c.user_two_id) and p.id in(c.user_one_id,c.user_two_id)) order by p.id limit 1;`);
      const peer=user(peerId);
      if (!peer) throw Error('All test peers already have a chat');
      const session=await this.session(peer);
      const response=await this.rpc(peer,'create_direct_conversation',{peer_user_id:owner.id},session);
      const chatId=typeof response==='string'?response:response?.id;
      if (!uuid.test(chatId)) throw Error('Unexpected create_direct_conversation result');
      await this.rpc(peer,'send_chat_message',{message_id:randomUUID(),target_conversation_id:chatId,message_type:'text',message_text:'Новый входящий чат из панели тестирования'},session);
      return {message:'Создан новый входящий чат',chatId};
    }
    if (name==='new-request') {
      const peerId=this.data(`select to_jsonb(p.id) from public.profiles p where p.id in (${ids(people.map(p=>p.id))})
        and not exists(select 1 from public.friendships f where '${owner.id}' in(f.user_one_id,f.user_two_id) and p.id in(f.user_one_id,f.user_two_id))
        and not exists(select 1 from public.friend_requests r where '${owner.id}' in(r.sender_id,r.recipient_id) and p.id in(r.sender_id,r.recipient_id)) order by p.id limit 1;`);
      const peer=user(peerId);
      if (!peer) throw Error('No free test peers remain');
      await this.rpc(peer,'send_friend_request',{peer_user_id:owner.id});
      return {message:'Новая входящая заявка отправлена',peerId:peer.id};
    }
    if (name==='accept-outgoing') {
      const request=this.data(`select jsonb_build_object('id',id,'peer',recipient_id) from public.friend_requests where sender_id='${owner.id}' order by created_at,id limit 1;`);
      if (!request) throw Error('No outgoing requests remain');
      await this.rpc(user(request.peer),'respond_friend_request',{target_request_id:request.id,accept_request:true});
      return {message:'Собеседник принял исходящую заявку',peerId:request.peer};
    }
    if (name==='cancel-incoming') {
      const request=this.data(`select jsonb_build_object('id',id,'peer',sender_id) from public.friend_requests where recipient_id='${owner.id}' order by created_at desc,id desc limit 1;`);
      if (!request) throw Error('No incoming requests remain');
      await this.rpc(user(request.peer),'cancel_friend_request',{target_request_id:request.id});
      return {message:'Отправитель отменил входящую заявку',peerId:request.peer};
    }
    throw Error('Unknown pagination lab action');
  }
  async cleanup() {
    if (!this.state) return {cleaned:0};
    const users=this.data(`select coalesce(jsonb_agg(id),'[]'::jsonb) from auth.users where raw_user_meta_data->>'pagination_lab'=${literal(marker)} and raw_user_meta_data->>'pagination_run'=${literal(this.state.run)};`);
    if (users.length) {
      for (const bucket of ['avatars','chat-images','chat-audio']) {
        const paths=this.data(`select coalesce(jsonb_agg(name),'[]'::jsonb) from storage.objects where bucket_id=${literal(bucket)} and split_part(name,'/',1) in (${ids(users)});`);
        for(let i=0;i<paths.length;i+=100) await this.request(`/storage/v1/object/${bucket}`,{method:'DELETE',body:{prefixes:paths.slice(i,i+100)}});
      }
      this.sql(`begin; delete from public.conversations where user_one_id in (${ids(users)}) or user_two_id in (${ids(users)}); commit;`);
      for (const id of users) await this.request(`/auth/v1/admin/users/${id}`,{method:'DELETE'});
    }
    this.state={marker,project:this.project,api:this.api,run:this.state.run,seeded:false,users:[],cleanedAt:new Date().toISOString()};
    this.save();
    return {cleaned:users.length};
  }
}
