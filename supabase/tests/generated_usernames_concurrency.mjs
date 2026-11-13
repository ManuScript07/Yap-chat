// Real concurrent transactions against LOCAL Docker Supabase only.
// No external requests, credentials, sequence resets or production access.
// Run: node supabase/tests/generated_usernames_concurrency.mjs
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';

const container = 'supabase_db_Yap_chat';
const args = ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'];
const ids = [];
const running = new Set();
const pending = new Set();
const tag = randomUUID().replaceAll('-', '').slice(0, 12);

function sql(input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 15000 });
  if (result.error || result.status !== 0) throw result.error ?? new Error(result.stderr);
  return result.stdout.trim();
}

function start(input, readyMarker) {
  const child = spawn('docker', args);
  running.add(child);
  let output = '', errors = '', readyResolve;
  const ready = new Promise(resolve => { readyResolve = resolve; });
  let settled = false;
  const done = new Promise((resolve, reject) => {
    child.stdout.on('data', data => {
      output += data;
      if (readyMarker && output.split(/\r?\n/).includes(readyMarker)) readyResolve();
    });
    child.stderr.on('data', data => { errors += data; });
    child.on('error', reject);
    child.on('close', code => {
      settled = true;
      running.delete(child);
      clearTimeout(timeout);
      if (code === 0) resolve(output.trim());
      else reject(new Error(errors || `psql exited with ${code}`));
    });
  });
  const timeout = setTimeout(() => {
    if (!settled) child.kill();
  }, 15000);
  // Avoid an unhandled rejection while the caller is checking lock state.
  done.catch(() => {});
  pending.add(done);
  done.then(() => pending.delete(done), () => pending.delete(done));
  child.stdin.end(input);
  return { ready: Promise.race([ready, done.then(() => {
    if (readyMarker && !output.includes(readyMarker)) throw new Error('Writer never reached ready marker');
  })]), done };
}

function newUser() {
  const id = randomUUID();
  ids.push(id);
  return id;
}

function createUser(id) {
  return `insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
    values('${id}',false,false,'{"name":"Username race fixture"}'::jsonb);`;
}

function authScope(id) {
  return `select set_config('request.jwt.claim.sub','${id}',true);
    select set_config('request.jwt.claims','{"sub":"${id}","role":"authenticated"}',true);
    set local role authenticated;`;
}

function nextFreeCandidate() {
  // Read only: don't consume or reserve the ticket. The manual writer leaves
  // its rename uncommitted, so the generator cannot see it before INSERT.
  return sql(`with next_ticket as (
      select last_value + case when is_called then 1 else 0 end as number
      from public.username_sequence
    ) select private.generated_username_for_number(number + offset_number)
    from next_ticket, generate_series(0,65536) offset_number
    where not exists (
      select 1 from public.profiles
      where lower(username)=private.generated_username_for_number(number + offset_number)
    ) order by offset_number limit 1;`);
}

async function race(mode) {
  const owner = newUser(), target = newUser();
  sql(`begin; ${createUser(owner)} ${mode === 'bootstrap' ? createUser(target) : ''} commit;`);
  if (mode === 'bootstrap') sql(`delete from public.profiles where id='${target}';`);
  const candidate = nextFreeCandidate();
  assert.match(candidate, /^u[0-9a-z]{7}$/);
  const appName = `username_${mode}_${tag}`;
  const writer = start(`begin; set local statement_timeout='12s'; ${authScope(owner)}
    select id from public.save_own_profile('Username race fixture',date '2000-01-01',
      'unspecified','${candidate}','','[]'::jsonb);
    select 'manual_ready'; select pg_sleep(3); commit;`, 'manual_ready');
  await writer.ready;
  const allocator = start(`begin; set local statement_timeout='12s';
    set local application_name='${appName}';
    ${mode === 'bootstrap'
      ? `${authScope(target)} select id from public.get_or_create_my_profile('Recovered',null,null);`
      : createUser(target)} commit;`);

  const deadline = Date.now() + 2500;
  let blocked = false;
  while (Date.now() < deadline) {
    blocked = sql(`select exists(select 1 from pg_stat_activity
      where application_name='${appName}' and wait_event_type='Lock' and wait_event='transactionid');`) === 't';
    if (blocked) break;
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  await Promise.all([writer.done, allocator.done]);
  assert(blocked, `${mode}: the intended username insertion race was not exercised`);
  const result = JSON.parse(sql(`select json_build_object(
    'owner',(select username from public.profiles where id='${owner}'),
    'target',(select username from public.profiles where id='${target}'),
    'consent',(select terms_accepted_at is not null from public.profiles where id='${target}'))::text;`));
  assert.equal(result.owner, candidate);
  assert.notEqual(result.target, candidate);
  assert.match(result.target, /^u[0-9a-z]{7}$/);
  assert.equal(result.consent, mode === 'bootstrap');
  console.log(`PASS: ${mode} waits for concurrent manual rename, then retries with a fresh username`);
}

try {
  await race('registration');
  await race('bootstrap');
  const parallelIds = Array.from({ length: 16 }, newUser);
  await Promise.all(parallelIds.map(id => start(`begin; set local statement_timeout='12s'; ${createUser(id)} commit;`).done));
  const quoted = parallelIds.map(id => `'${id}'`).join(',');
  assert.equal(sql(`select count(*)||':'||count(distinct lower(username)) from public.profiles where id in (${quoted});`), '16:16');
  console.log('PASS: 16 parallel registrations have 16 distinct usernames');

  const manualCandidate = sql(`select username from public.profiles where id='${parallelIds[0]}';`);
  const duplicate = spawnSync('docker', args, {
    input: `begin; ${authScope(parallelIds[1])}
      select id from public.save_own_profile('Username race fixture',date '2000-01-01',
        'unspecified','${manualCandidate}','','[]'::jsonb); commit;`, encoding: 'utf8', timeout: 15000,
  });
  assert.notEqual(duplicate.status, 0);
  assert.match(duplicate.stderr, /profiles_username_lower_unique/);
  console.log('PASS: manual duplicate username is rejected, not silently replaced');
} finally {
  // Wait for all bounded workers, including siblings of a failed worker,
  // before cleanup so none can commit a fixture after it was deleted.
  await Promise.allSettled([...pending]);
  for (const child of running) child.kill();
  // These random UUIDs belong only to this test; no broad cleanup or reset.
  if (ids.length) {
    const quoted = ids.map(id => `'${id}'`).join(',');
    sql(`begin; delete from public.profiles where id in (${quoted});
      delete from auth.users where id in (${quoted}); commit;`);
  }
}
