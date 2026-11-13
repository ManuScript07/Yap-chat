// Transactional SQL contracts against the existing local Docker database only.
// No schema reset, remote configuration, credentials, or production endpoints.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';

const output = '.dart_tool/message_deletion_validation';
mkdirSync(output, { recursive: true });
function run(source, timeout = 150000) {
  return spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat',
    'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], {
    // Server deadline also stops work if the Docker CLI is interrupted.
    input: `set statement_timeout = '120s';\n${source}`,
    encoding: 'utf8', timeout, maxBuffer: 8 * 1024 * 1024,
  });
}
const snapshot = () => {
  const result = run(`select jsonb_build_object(
    'users', (select count(*) from auth.users),
    'chats', (select count(*) from public.conversations),
    'messages', (select count(*) from public.messages),
    'attachments', (select count(*) from public.message_attachments));`);
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return result.stdout.trim();
};
const before = snapshot();
const results = [];
for (const file of readdirSync('supabase/tests').filter(f => f.endsWith('.sql')).sort()) {
  const source = readFileSync(`supabase/tests/${file}`, 'utf8');
  assert(/^begin;/im.test(source) && /rollback;/im.test(source), `Non-transactional test: ${file}`);
  const result = run(source);
  writeFileSync(`${output}/${file}.log`, `${result.stdout ?? ''}\n${result.stderr ?? ''}\n${result.error ?? ''}`);
  const passed = result.status === 0;
  results.push({ file, passed });
  console.log(`${passed ? 'PASS' : 'FAIL'} ${file}`);
  // Never continue after a transport timeout: the status of its backend may be
  // unknown. A new run must first inspect/cancel that specific local test.
  if (result.error) throw result.error;
}
const after = snapshot();
const report = { sql_tests: results, fixtures_unchanged: after === before };
writeFileSync(`${output}/sql_regression.json`, JSON.stringify(report, null, 2));
assert.equal(after, before, 'Fixture counts changed despite rollback');
assert(results.every(r => r.passed), 'SQL regression failed; see per-test logs');
console.log(JSON.stringify({ passed: true, sql_tests_passed: results.length, fixtures_unchanged: true }));
