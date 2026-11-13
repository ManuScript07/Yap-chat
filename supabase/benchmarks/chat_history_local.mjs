// Local Docker only. Never reads .env or connects to a remote project.
// Run: node supabase/benchmarks/chat_history_local.mjs [--flutter]
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';

const base = 'http://127.0.0.1:54321';
const output = process.env.CHAT_HISTORY_BENCHMARK_OUTPUT ?? '.dart_tool/chat_history_validation';
assert(/^\.dart_tool\/[a-zA-Z0-9_/-]+$/.test(output) && !output.includes('..'), 'Unsafe benchmark output path');
mkdirSync(output, { recursive: true });
function sql(input) {
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat',
    'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'],
  { input, encoding: 'utf8', timeout: 180000, maxBuffer: 16 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}
function env(container) {
  const result = spawnSync('docker', ['inspect', '--format', '{{json .Config.Env}}', container], { encoding: 'utf8' });
  assert.equal(result.status, 0, 'Local Docker container unavailable');
  return Object.fromEntries(JSON.parse(result.stdout).map(value => {
    const at = value.indexOf('='); return [value.slice(0, at), value.slice(at + 1)];
  }));
}
const secret = env('supabase_auth_Yap_chat').GOTRUE_JWT_SECRET;
const anon = env('supabase_storage_Yap_chat').ANON_KEY;
assert(secret && anon, 'Local keys unavailable');
function jwt(user) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = encode({ alg: 'HS256', typ: 'JWT' }) + '.' + encode({ sub: user,
    role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 });
  return data + '.' + createHmac('sha256', secret).update(data).digest('base64url');
}
function stats(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  const percentile = p => +sorted[Math.ceil(sorted.length * p) - 1].toFixed(3);
  return { samples: samples.length, p50_ms: percentile(.5), p95_ms: percentile(.95), max_ms: percentile(1) };
}
async function rpc(fixture, name, params, user = fixture.a) {
  const start = performance.now();
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, { method: 'POST',
    headers: { apikey: anon, Authorization: `Bearer ${jwt(user)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(params), signal: AbortSignal.timeout(15000) });
  const raw = await response.text();
  assert(response.ok, `${name}: ${response.status} ${raw}`);
  return { rows: JSON.parse(raw), ms: performance.now() - start, bytes: Buffer.byteLength(raw) };
}
const fixtures = [];
const report = { environment: { base, node: process.version,
  postgres: sql('select version();'), generated_at: new Date().toISOString() }, results: [] };
try {
  for (const size of [1000, 10000, 100000]) {
    const [a, b] = [randomUUID(), randomUUID()].sort();
    const f = { a, b, chat: randomUUID(), size }; fixtures.push(f);
    // Suppress ONLY synthetic bulk-message insert side effects, in this session
    // and transaction. Real RPC actions retain all triggers and access checks.
    sql(`begin;
      insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
      values('${a}',false,false,'{}'),('${b}',false,false,'{}');
      insert into public.conversations(id,user_one_id,user_two_id,created_by)
      values('${f.chat}','${a}','${b}','${a}');
      insert into public.conversation_members(conversation_id,user_id)
      values('${f.chat}','${a}'),('${f.chat}','${b}');
      set local session_replication_role=replica;
      insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
      select md5('${f.chat}:'||i)::uuid,'${f.chat}',case when i%2=0 then '${a}'::uuid else '${b}'::uuid end,
        'text',repeat('synthetic message ',12)||i,
        '2026-01-01T00:00:00Z'::timestamptz+(i/10)*interval '1 second'+(i%3)*interval '1 microsecond'
      from generate_series(1,${size}) i;
      set local session_replication_role=origin;
      do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
        perform private.rebuild_chat_unread_projection(array['${f.chat}']::uuid[]);end if;end $f$;
      commit;`);
    sql('analyze public.messages;');
    const target = sql(`select id from public.messages where conversation_id='${f.chat}'
      order by created_at,id offset ${Math.floor(size / 2)} limit 1;`);
    f.target = target;
    if (size === 100000) {
      report.environment.window_plans = [];
      for (const mode of ['auto', 'force_generic_plan']) {
        const trace = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat',
          'psql', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], {
          input: `load 'auto_explain'; set auto_explain.log_min_duration='0ms';
          set auto_explain.log_format=json; set plan_cache_mode=${mode};
          set auto_explain.log_nested_statements=on; set auto_explain.log_analyze=on;
          set auto_explain.log_buffers=on; set auto_explain.log_timing=off;
          set client_min_messages=log;
          begin; select set_config('request.jwt.claim.sub','${a}',true);
          set local role authenticated;
          select count(*) from public.get_conversation_messages('${f.chat}');
          select count(*) from public.get_conversation_message_window('${f.chat}','${target}');
          select count(*) from public.get_conversation_message_window('${f.chat}',null,
            (select created_at from public.messages where id='${target}'),'${target}',60); rollback;`,
          encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024,
        });
        writeFileSync(`${output}/postgres_100000_nested_plans_${mode}.txt`, trace.stderr);
        report.environment.nested_auto_explain = trace.status === 0
          ? 'available' : 'unavailable under the local postgres role; see trace';
        assert.equal(trace.status, 0, 'Nested EXPLAIN failed');
        const plans = jsonPlans(trace.stderr).filter(p => /older as\s*\(/i.test(p['Query Text'] ?? ''));
        assert.equal(plans.length, 2, 'Both target and newer-cursor nested plans are required');
        for (const [index, plan] of plans.entries()) {
          const scans = [];
          function visit(node) {
            if (node['Relation Name'] === 'messages' && node['Index Name'] === 'messages_conversation_created_idx'
              && node['Actual Loops'] > 0) {
              scans.push({ index_condition: node['Index Cond'], rows: node['Actual Rows'],
                removed_by_filter: node['Rows Removed by Filter'] ?? 0,
                cursor_seek: /ROW\([^)]*created_at[^)]*id[^)]*\)\s*(?:<=|>)\s*ROW/.test(node['Index Cond'] ?? '') });
            }
            for (const child of node.Plans ?? []) visit(child);
          }
          visit(plan.Plan);
          if (process.env.EXPECT_CONVERSATION_WINDOW_SEEK === '1') {
            assert.equal(scans.length, index === 0 ? 2 : 1, 'Unexpected active history scans');
            assert(scans.every(scan => scan.cursor_seek && scan.rows <= (index === 0 ? 30 : 60) && scan.removed_by_filter === 0),
              `Unbounded history scan: ${JSON.stringify(scans)}`);
          }
          report.environment.window_plans.push({ mode, operation: index === 0 ? 'target' : 'newer', scans });
        }
      }
    }
    const boundary = JSON.parse(sql(`select json_build_object('id',id,'at',created_at) from public.messages
      where conversation_id='${f.chat}' order by created_at,id offset ${Math.floor(size * .9)} limit 1;`));
    const plans = sql(`begin; select set_config('request.jwt.claim.sub','${a}',true);
      set local role authenticated;
      explain (analyze,buffers,format json) select * from public.get_conversation_messages('${f.chat}');
      explain (analyze,buffers,format json) select * from public.get_conversation_messages('${f.chat}','${boundary.at}','${boundary.id}',60);
      rollback;`);
    writeFileSync(`${output}/postgres_${size}_rpc_plans.txt`, plans);
    // Explain the underlying keyset separately: outer PL/pgSQL plans otherwise
    // expose only a Function Scan, not the inner index access.
    const keysetPlan = JSON.parse(sql(`explain (analyze,buffers,format json)
      select * from public.messages where conversation_id='${f.chat}'
      and (created_at,id)<('${boundary.at}'::timestamptz,'${boundary.id}'::uuid)
      order by created_at desc,id desc limit 60;`));
    writeFileSync(`${output}/postgres_${size}_keyset_plan.json`, JSON.stringify(keysetPlan, null, 2));
    const operations = [
      ['head', 'get_conversation_messages', { target_conversation_id: f.chat, page_size: 60 }],
      ['deep_page', 'get_conversation_messages', { target_conversation_id: f.chat,
        before_created_at: boundary.at, before_message_id: boundary.id, page_size: 60 }],
      ['reply_window', 'get_conversation_message_window', { target_conversation_id: f.chat, target_message_id: target }],
      ['newer_page', 'get_conversation_message_window', { target_conversation_id: f.chat,
        after_created_at: boundary.at, after_message_id: boundary.id, page_size: 60 }],
    ];
    const result = { size, operations: {} };
    let head;
    for (const [label, name, params] of operations) {
      const first = await rpc(f, name, params);
      assert.equal(first.rows.length, 60);
      assert.equal(new Set(first.rows.map(r => r.id)).size, 60);
      if (label === 'head') head = first.rows;
      if (label === 'reply_window') assert(first.rows.some(r => r.id === target));
      const samples = [];
      for (let i = 0; i < 8; i++) {
        const response = await rpc(f, name, params);
        assert.deepEqual(response.rows.map(r => r.id), first.rows.map(r => r.id));
        samples.push(response.ms);
      }
      result.operations[label] = { first_ms: +first.ms.toFixed(3), response_bytes: first.bytes, ...stats(samples) };
    }
    const visibleSamples = [];
    for (let i = 0; i < 8; i++) {
      const r = await rpc(f, 'get_visible_conversation_message_states', {
        target_conversation_id: f.chat, message_ids: head.map(r => r.id) });
      assert.equal(r.rows.length, 60); visibleSamples.push(r.ms);
    }
    result.operations.visible_state = stats(visibleSamples);
    const concurrent = await Promise.all(Array.from({ length: 10 }, () => rpc(f,
      'get_conversation_messages', { target_conversation_id: f.chat, page_size: 60 })));
    assert(concurrent.every(r => r.rows.length === 60));
    result.operations.parallel_10_head = stats(concurrent.map(r => r.ms));
    result.keyset_execution_ms = keysetPlan[0]['Execution Time'];
    result.keyset_uses_cursor_index = JSON.stringify(keysetPlan).includes('messages_conversation_created_idx');
    report.results.push(result);
    console.log(JSON.stringify(result));
  }
  if (process.argv.includes('--flutter')) {
    const f = fixtures[2];
    const run = spawnSync('flutter', ['test',
      'test/repositories/chat/local_chat_history_integration_test.dart', '--reporter', 'expanded'],
    { shell: true, encoding: 'utf8', timeout: 180000, env: { ...process.env,
      CHAT_TEST_ANON: anon, CHAT_TEST_TOKEN: jwt(f.b), CHAT_TEST_USER: f.b,
      CHAT_TEST_PEER: f.a, CHAT_TEST_CHAT: f.chat, CHAT_TEST_TARGET: f.target } });
    writeFileSync(`${output}/real_repository.log`, `${run.stdout}\n${run.stderr}`);
    assert.equal(run.status, 0, 'Real repository integration test failed; see .dart_tool/chat_history_validation/real_repository.log');
    report.real_repository_passed = true;
  }
} finally {
  for (const f of fixtures.reverse()) {
    // Exact generated IDs only. Normal cascades clean receipts/reactions too.
    sql(`begin; delete from public.conversations where id='${f.chat}';
      delete from public.profiles where id in ('${f.a}','${f.b}');
      delete from auth.users where id in ('${f.a}','${f.b}'); commit;`);
  }
  report.cleaned_up = true;
  writeFileSync(`${output}/server.json`, JSON.stringify(report, null, 2));
}

// auto_explain logs nested JSON objects among psql log/context lines.
function jsonPlans(log) {
  const plans = [];
  let cursor = 0;
  while ((cursor = log.indexOf('plan:', cursor)) >= 0) {
    const start = log.indexOf('{', cursor);
    if (start < 0) break;
    let depth = 0, quoted = false, escaped = false;
    for (let end = start; end < log.length; end++) {
      const char = log[end];
      if (quoted) {
        if (escaped) escaped = false;
        else if (char === '\\') escaped = true;
        else if (char === '"') quoted = false;
      } else if (char === '"') quoted = true;
      else if (char === '{') depth++;
      else if (char === '}' && --depth === 0) {
        plans.push(JSON.parse(log.slice(start, end + 1)));
        cursor = end + 1;
        break;
      }
    }
    if (cursor <= start) break;
  }
  return plans;
}
