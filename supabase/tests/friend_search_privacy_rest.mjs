// Local Docker Supabase only. Uses real PostgREST RPCs and temporary accounts.
// Local signing keys stay in memory and are never printed. Fixtures are removed
// in finally; this script cannot target a remote Supabase project.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomBytes, randomUUID } from 'node:crypto';

const url = 'http://127.0.0.1:54321';
function containerEnv(container) {
  const result = spawnSync('docker', [
    'inspect', '--format', '{{json .Config.Env}}', container,
  ], { encoding: 'utf8' });
  assert.equal(result.status, 0, 'Local Supabase container unavailable');
  return Object.fromEntries(JSON.parse(result.stdout).map((value) => {
    const separator = value.indexOf('=');
    return [value.slice(0, separator), value.slice(separator + 1)];
  }));
}
const secret = containerEnv('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anonKey = containerEnv('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anonKey, 'Local Supabase signing configuration unavailable');

function token(userId) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({
    sub: userId, role: 'authenticated', aud: 'authenticated',
    exp: Math.floor(Date.now() / 1000) + 300,
  })}`;
  return `${data}.${createHmac('sha256', secret).update(data).digest('base64url')}`;
}
function sql(input) {
  const result = spawnSync('docker', [
    'exec', '-i', 'supabase_db_Yap_chat', 'psql', '-X', '-U', 'postgres',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt',
  ], { input, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
}
async function rpc(userId, name, params) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: anonKey, Authorization: `Bearer ${token(userId)}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(params), signal: AbortSignal.timeout(10000),
  });
  const body = await response.text();
  const data = body.length === 0 ? null : JSON.parse(body);
  assert(response.ok, `${name}: ${JSON.stringify(data)}`);
  return data;
}

const viewer = randomUUID();
const target = randomUUID();
const suffix = randomBytes(6).toString('hex');
const username = `privacy_${suffix}`;
const displayName = `Privacyrest${suffix}`;
const search = (searchQuery) => rpc(viewer, 'search_friend_candidates', {
  search_query: searchQuery, result_limit: 10,
});
const setting = (key, enabled) => rpc(target, 'set_my_search_privacy_setting', {
  setting_key: key, is_enabled: enabled,
});
let checks = 0;
async function expectSearch(query, relationship) {
  const results = await search(query);
  assert.deepEqual(results.map((candidate) => candidate.id),
    relationship === null ? [] : [target]);
  if (relationship !== null) assert.equal(results[0].relationship, relationship);
  checks++;
}

try {
  sql(`begin;
    insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
    values ('${viewer}', false, false, '{"name":"Privacy viewer"}'),
           ('${target}', false, false, '{"name":"Privacy target"}');
    update public.profiles set onboarding_completed = true,
      username = '${username}', display_name = '${displayName}' where id = '${target}';
    update public.profiles set onboarding_completed = true where id = '${viewer}';
    commit;`);

  await expectSearch(`@${username}`, 'none');
  await expectSearch(displayName, 'none');
  await setting('username', false);
  await expectSearch(`  @${username.toUpperCase()}  `, null);
  await expectSearch(displayName, 'none');
  await setting('name', false);
  await expectSearch(displayName, null);
  const legacyProfiles = await fetch(
    `${url}/rest/v1/public_profiles?username=eq.${username}&select=id,username`,
    {
      headers: { apikey: anonKey, Authorization: `Bearer ${token(viewer)}` },
      signal: AbortSignal.timeout(10000),
    },
  );
  assert.equal(legacyProfiles.status, 403,
    'Unused legacy profile view must not bypass discovery privacy');
  checks++;
  assert.equal(await rpc(viewer, 'resolve_shared_profile_username', {
    shared_username: username,
  }), target);
  checks++;

  const requestId = await rpc(viewer, 'send_friend_request', { peer_user_id: target });
  await expectSearch(`@${username}`, null);
  await expectSearch(displayName, null);
  await rpc(target, 'respond_friend_request', { target_request_id: requestId, accept_request: true });
  await expectSearch(`@${username}`, 'friend');
  await expectSearch(displayName, 'friend');
  await rpc(viewer, 'remove_friend', { friend_user_id: target });
  await expectSearch(`@${username}`, null);
  await expectSearch(displayName, null);

  await setting('username', true);
  await expectSearch(`@${username}`, 'none');
  await expectSearch(displayName, null);
  await setting('name', true);
  await expectSearch(displayName, 'none');
  await rpc(target, 'block_user', { target_user_id: viewer });
  await expectSearch(`@${username}`, null);
  await expectSearch(displayName, null);
  const profile = await rpc(viewer, 'get_viewed_profile', {
    target_user_id: target, should_register_view: false,
  });
  // Existing blocked-profile reads may be absent under profile RLS or return
  // the redacted identity. Neither path may expose the actual profile data.
  assert(profile.length <= 1);
  if (profile.length !== 0) {
    assert.equal(profile[0].relationship, 'blocked');
    assert.equal(profile[0].username, '');
    assert.deepEqual(profile[0].photos, []);
    assert.equal(profile[0].avatar_url, null);
    assert.equal(profile[0].avatar_storage_path, null);
  }
  checks++;
  console.log(`PASS: ${checks} local PostgREST search/privacy/friendship checks`);
} finally {
  sql(`begin;
    delete from public.profiles where id in ('${viewer}', '${target}');
    delete from auth.users where id in ('${viewer}', '${target}');
    commit;`);
}
