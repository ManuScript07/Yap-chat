// LOCAL ONLY: replay the exact migration in psql autocommit, as separate commands.
// A disposable database keeps the project's running local schema/data untouched.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const container = 'supabase_db_Yap_chat';
const database = `unread_migration_${randomUUID().replaceAll('-', '')}`;
assert(/^unread_migration_[a-f0-9]{32}$/.test(database));
const path = 'supabase/migrations/20261025230324_add_chat_unread_projection.sql';
const migration = readFileSync(path, 'utf8');
const old = spawnSync('git', ['show', `7356f0c:${path}`], { encoding: 'utf8' });
assert.equal(old.status, 0, old.stderr);
const logs = [];
function sql(source, db = database) {
  const result = spawnSync('docker', ['exec', '-i', container, 'psql', '-X',
    '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-qAt'], {
    input: source, encoding: 'utf8', timeout: 135000, maxBuffer: 4 * 1024 * 1024,
  });
  logs.push(`${result.stdout ?? ''}\n${result.stderr ?? ''}`);
  if (result.error) throw result.error;
  return result;
}
function pass(source, db) {
  const result = sql(source, db);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}
const actor = 'a8680000-0000-0000-0000-000000000001';
const peer = 'a8680000-0000-0000-0000-000000000002';
// Only the prerequisite relations/functions used by this migration are needed.
// Full real Supabase schema/RLS contracts are covered by the separate SQL matrix.
const base = `
create schema private; create schema auth;
create function auth.uid() returns uuid language sql stable as
$$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function private.require_active_account() returns void language plpgsql as $$begin return;end$$;
create function private.consume_chat_summary_refresh_quota(integer) returns void language plpgsql as $$begin return;end$$;
create function private.get_chat_list_page_impl(timestamptz,uuid,integer,text)
returns jsonb language sql as $$select jsonb_build_object('items','[]'::jsonb)$$;
create table public.conversation_members(conversation_id uuid,user_id uuid,
  hidden_at timestamptz,cleared_at timestamptz,is_muted boolean not null default false,
  primary key(conversation_id,user_id));
create table public.messages(id uuid primary key,conversation_id uuid,sender_id uuid,
  created_at timestamptz not null,deleted_for_everyone_at timestamptz);
create table public.message_receipts(message_id uuid,user_id uuid,read_at timestamptz,
  primary key(message_id,user_id));
create table public.message_hidden_for_users(message_id uuid,user_id uuid,primary key(message_id,user_id));
insert into public.conversation_members(conversation_id,user_id)
select ('b8680000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,owner
from generate_series(1,4)i cross join (values('${actor}'::uuid),('${peer}'::uuid))owners(owner);
insert into public.messages(id,conversation_id,sender_id,created_at)
select ('c8680000-0000-0000-0000-'||lpad(((chat-1)*20+n)::text,12,'0'))::uuid,
 ('b8680000-0000-0000-0000-'||lpad(chat::text,12,'0'))::uuid,'${peer}',
 '2026-01-01'::timestamptz+n*interval '1 second'
from generate_series(1,4)chat cross join generate_series(1,20)n;
insert into public.message_receipts select id,'${actor}',now() from public.messages
where id<='c8680000-0000-0000-0000-000000000003';
insert into public.message_hidden_for_users values('c8680000-0000-0000-0000-000000000004','${actor}');
update public.messages set deleted_for_everyone_at=now() where id='c8680000-0000-0000-0000-000000000005';
update public.conversation_members set is_muted=true where conversation_id='b8680000-0000-0000-0000-000000000002' and user_id='${actor}';
update public.conversation_members set hidden_at=now() where conversation_id='b8680000-0000-0000-0000-000000000003' and user_id='${actor}';
update public.conversation_members set cleared_at='2026-01-01 00:00:10+00' where conversation_id='b8680000-0000-0000-0000-000000000004' and user_id='${actor}';
`;
let created = false;
try {
  pass(`create database ${database} template template0;`, 'postgres');
  created = true;
  pass(base);
  const original = sql(old.stdout);
  assert.notEqual(original.status, 0);
  assert.match(original.stderr, /25P01/);
  const predecessor = pass(`select pg_get_functiondef('private.get_chat_list_page_impl(timestamptz,uuid,integer,text)'::regprocedure);`);
  const marker = "notify pgrst,'reload schema';";
  assert.equal(migration.split(marker).length, 2);
  const interrupted = sql(migration.replace(marker,
    "raise exception using errcode='ZX001',message='migration_atomicity_probe';"));
  assert.notEqual(interrupted.status, 0);
  assert.match(interrupted.stderr, /ZX001/);
  assert.equal(pass(`select to_regclass('private.chat_unread_counts') is null
    and to_regclass('private.chat_unread_messages') is null
    and to_regprocedure('private.get_chat_list_page_without_unread_impl(timestamptz,uuid,integer,text)') is null
    and to_regprocedure('private.sync_chat_unread_messages_impl(uuid[],uuid[],text)') is null;`), 't');
  assert.equal(pass(`select pg_get_functiondef('private.get_chat_list_page_impl(timestamptz,uuid,integer,text)'::regprocedure);`), predecessor);
  pass(migration);
  pass(`select set_config('request.jwt.claim.sub','${actor}',false);
    do $$begin
    if private.get_chat_unread_total_impl()<>25 then raise exception 'Wrong autocommit backfill total';end if;
    if (select count(*) from private.chat_unread_messages)<>65 then raise exception 'Wrong ledger';end if;
    if has_table_privilege('authenticated','private.chat_unread_messages','select')
    or has_function_privilege('anon','public.get_chat_unread_state(uuid[])','execute') then raise exception 'ACL changed';end if;
    end$$;
    insert into public.messages values('d8680000-0000-0000-0000-000000000001',
      'b8680000-0000-0000-0000-000000000001','${peer}',now(),null);
    do $$begin if private.get_chat_unread_total_impl()<>26 then raise exception 'Insert trigger missing';end if;end$$;
    insert into public.message_receipts values('d8680000-0000-0000-0000-000000000001','${actor}',now());
    do $$begin if private.get_chat_unread_total_impl()<>25 then raise exception 'Read trigger missing';end if;
    if (public.get_chat_list_page(null,null,1,'')->>'unread_total')::bigint<>25 then raise exception 'Page wrapper missing';end if;end$$;`);
  console.log(JSON.stringify({ passed: true, original_25P01_reproduced: true,
    autocommit_migration: true, forced_error_rolls_back_schema_and_backfill: true,
    retry_after_rollback: true, populated_backfill: true, post_commit_insert_read: true }));
} finally {
  if (created) pass(`drop database ${database} with (force);`, 'postgres');
  writeFileSync('tmp/chat_unread_migration_autocommit.log', logs.join('\n'));
}
