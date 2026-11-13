// Local Docker only: exact old/new projection comparison, no schema reset.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';

const output = '.dart_tool/conversation_window_seek';
mkdirSync(output, { recursive: true });
function sql(input, timeout = 180000) {
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat',
    'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'],
  { input: `set statement_timeout='${Math.max(1000, timeout - 5000)}ms';\n${input}`,
    encoding: 'utf8', timeout, maxBuffer: 16 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return result.stdout.trim();
}
async function matrix(input) {
  const started = performance.now();
  const child = spawn('docker', ['exec', '-i', 'supabase_db_Yap_chat',
    'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt']);
  const stdout = [], stderr = [];
  child.stdout.on('data', chunk => stdout.push(chunk));
  child.stderr.on('data', chunk => {
    stderr.push(chunk);
    process.stdout.write(chunk);
  });
  // The PostgreSQL deadline expires first, rolling back the fixture transaction
  // even if the Docker CLI connection is interrupted. Longer than a single RPC:
  // this one statement performs 1340 cases with four SELECTs in each case.
  const deadline = setTimeout(() => child.kill(), 920000);
  try {
    child.stdin.end(`set application_name='yapchat_window_matrix';
      set statement_timeout='900s';\n${input}`);
    const status = await new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('close', resolve);
      child.stdin.on('error', reject);
    });
    const result = Buffer.concat(stdout).toString('utf8');
    writeFileSync(`${output}/equivalence.log`, result);
    writeFileSync(`${output}/equivalence.stderr.log`, Buffer.concat(stderr).toString('utf8'));
    assert.equal(status, 0, 'Window matrix failed; see equivalence logs');
    return { output: result.trim(), elapsed_ms: +(performance.now() - started).toFixed(3) };
  } finally {
    clearTimeout(deadline);
  }
}
const before = sql(`select json_build_object('users',(select count(*) from auth.users),
  'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages));`);
const original = readFileSync('supabase/migrations/202609240002_add_conversation_message_window.sql', 'utf8')
  .replaceAll('\r\n', '\n');
const reference = original.slice(original.indexOf('create function private.'), original.indexOf('\ncreate function public.'))
  .replace('create function private.get_conversation_message_window_impl', 'create function pg_temp.legacy_conversation_window');
assert(reference.includes('cross join anchor') && reference.trimEnd().endsWith('$$;'));
const cases = readFileSync('supabase/tests/fixtures/conversation_window_seek_cases.sql', 'utf8');
console.log('Starting all 1340 window equivalence cases (original reference vs current DB functions)');
const matrixResult = await matrix(`begin; create temp table window_seek_bootstrap(id integer);\n${reference}\n${cases}\nrollback;`);
const equivalence = matrixResult.output;
const comparison = JSON.parse(equivalence.split('\n').at(-1));
assert.equal(comparison.equivalent_window_cases, 1340, 'Incomplete equivalence matrix');
writeFileSync(`${output}/equivalence.log`, equivalence);

const regression = [];
for (const file of readdirSync('supabase/tests').filter(f => f.endsWith('.sql')).sort()) {
  const source = readFileSync(`supabase/tests/${file}`, 'utf8');
  assert(/^begin;/im.test(source) && /rollback;/im.test(source), `Non-transactional test: ${file}`);
  const run = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat',
    'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'],
  { input: `set statement_timeout='110s';\n${source}`,
    encoding: 'utf8', timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
  writeFileSync(`${output}/${file}.log`, `${run.stdout}\n${run.stderr}`);
  regression.push({ file, passed: run.status === 0 });
  console.log(`${run.status === 0 ? 'PASS' : 'FAIL'} ${file}`);
}
const after = sql(`select json_build_object('users',(select count(*) from auth.users),
  'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages));`);
assert.equal(after, before, 'Test fixtures survived rollback');
const report = { equivalence: comparison, matrix_elapsed_ms: matrixResult.elapsed_ms,
  sql_tests: regression, fixtures_unchanged: true };
writeFileSync(`${output}/regression.json`, JSON.stringify(report, null, 2));
assert(regression.every(result => result.passed), 'SQL regression failed; see per-test logs');
console.log(JSON.stringify({ equivalence: comparison, sql_tests_passed: regression.length, fixtures_unchanged: true }));
