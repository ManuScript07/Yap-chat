// Compare actual old/new functions on identical rollback-only local fixtures.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

// Last legacy implementation, later moved to private without changing its body.
const legacyMigration = readFileSync('supabase/migrations/202608190004_fix_conversation_clear_boundaries.sql','utf8');
const original = legacyMigration.match(/create or replace function public\.mark_conversations_read\(conversation_ids uuid\[\]\)[\s\S]*?\$\$;/i)?.[0];
assert(original, 'Legacy function definition missing');
const beforeDefinition = original.replace(/function public\.mark_conversations_read/i, 'function pg_temp.bulk_read_before');
function run(source) {
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_Yap_chat', 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt'], {
    input: `set statement_timeout='90s';\n${source}`, encoding: 'utf8', timeout: 120000, maxBuffer: 4*1024*1024,
  });
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return result;
}
const user = 'a6500000-0000-0000-0000-000000000001';
const peer = 'a6500000-0000-0000-0000-000000000002';
const chat = 'a6500000-0000-0000-0000-000000000003';
const results = [];
for (const total of [10000, 100000]) {
  for (const unread of [0, 60, total]) {
    let source = `begin;
      ${beforeDefinition};
      insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values ('${user}',false,false,'{}'),('${peer}',false,false,'{}');
      insert into public.conversations(id,user_one_id,user_two_id,created_by) values ('${chat}','${user}','${peer}','${peer}');
      insert into public.conversation_members(conversation_id,user_id) values ('${chat}','${user}'),('${chat}','${peer}');
      alter table public.messages disable trigger user;
      insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
      select ('a6500000-0000-0001-0000-'||lpad(i::text,12,'0'))::uuid,'${chat}','${peer}','text','bench', '2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,${total}) i;
      alter table public.messages enable trigger user;
      insert into public.message_receipts(message_id,user_id,read_at)
      select id,'${user}','2021-01-01' from public.messages where conversation_id='${chat}' order by id limit ${total-unread};
      do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
        perform private.rebuild_chat_unread_projection(array['${chat}']::uuid[]);end if;end $f$;
      analyze public.messages; analyze public.message_receipts;
      select set_config('request.jwt.claim.sub','${user}',true);
    `;
    for (const variant of ['before','after']) {
      source += `
        \\echo PLAN_${variant}
        explain (analyze, buffers, format json)
        select m.id from public.messages m
        where m.conversation_id='${chat}' and m.sender_id<>'${user}'
          and m.deleted_for_everyone_at is null
          and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id='${user}')
          ${variant==='after' ? `and not exists(select 1 from public.message_receipts r where r.message_id=m.id and r.user_id='${user}')` : ''};
        \\echo ENDPLAN_${variant}
      `;
    }
    for (let repeat=0; repeat<6; repeat++) {
      for (const variant of repeat % 2 ? ['after', 'before'] : ['before', 'after']) {
        const fn = variant === 'before' ? 'pg_temp.bulk_read_before' : 'private.mark_conversations_read_impl';
        source += `savepoint sample;
          do $b$ declare started timestamptz:=clock_timestamp(); event_count integer; begin
            perform ${fn}(array['${chat}']::uuid[]);
            select count(*) into event_count from realtime.messages where payload->>'reason'='read' and payload->>'conversation_id'='${chat}';
            raise notice 'SAMPLE ${variant} ${repeat} % %',extract(epoch from clock_timestamp()-started)*1000,event_count;
          end $b$;
          rollback to sample;
        `;
      }
    }
    source += 'rollback;';
    const result = run(source);
    for (const variant of ['before','after']) {
      const plan = result.stdout.match(new RegExp(`PLAN_${variant}\\r?\\n([\\s\\S]*?)\\r?\\nENDPLAN_${variant}`));
      assert(plan, 'Missing diagnostic candidate plan');
      writeFileSync(`tmp/chat_bulk_read_plan_${total}_${unread}_${variant}.json`,JSON.stringify(JSON.parse(plan[1]),null,2));
    }
    const samples = [...result.stderr.matchAll(/SAMPLE (before|after) (\d+) ([\d.]+) (\d+)/g)].map(m=>({variant:m[1],repeat:+m[2],ms:+m[3],events:+m[4]}));
    assert.equal(samples.length,12);
    const median = variant => {
      const times=samples.filter(s=>s.variant===variant && s.repeat>1).map(s=>s.ms).sort((a,b)=>a-b);
      return +(0.5*(times[1]+times[2])).toFixed(3);
    };
    const row = {total,unread,before_ms:median('before'),after_ms:median('after'),before_events:samples.find(s=>s.variant==='before').events,after_events:samples.find(s=>s.variant==='after').events};
    results.push(row); console.log(JSON.stringify(row));
  }
}
writeFileSync('tmp/chat_bulk_read_benchmark.json',JSON.stringify(results,null,2));
