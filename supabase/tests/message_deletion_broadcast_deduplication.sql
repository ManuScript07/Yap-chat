-- Local contract: count database-produced events, not just their existence.
-- Every fixture, helper, tombstone and broadcast rolls back.
begin;

create temp table deletion_seen_events (id uuid primary key);

create function pg_temp.expect_deletion_events(
  author_count integer, peer_count integer, shared_count integer,
  expected_reason text, expected_message_id text,
  shared_has_id boolean default true
)
returns void language plpgsql as $$
declare
  actual integer[];
begin
  select array[
    count(*) filter (where topic = 'user:78000000-0000-0000-0000-000000000001:chats'),
    count(*) filter (where topic = 'user:78000000-0000-0000-0000-000000000002:chats'),
    count(*) filter (where topic = 'chat:79000000-0000-0000-0000-000000000001')
  ] into actual
  from realtime.messages e
  where payload->>'conversation_id' = '79000000-0000-0000-0000-000000000001'
    and not exists (select 1 from deletion_seen_events s where s.id = e.id);
  if actual <> array[author_count, peer_count, shared_count] then
    raise exception 'Expected event counts %, got %',
      array[author_count, peer_count, shared_count], actual;
  end if;

  if exists (
    select 1 from realtime.messages e
    where payload->>'conversation_id' = '79000000-0000-0000-0000-000000000001'
      and not exists (select 1 from deletion_seen_events s where s.id = e.id)
      and (
        event is distinct from 'changed' or private is distinct from true
        or payload->>'reason' is distinct from expected_reason
        or payload->>'message_id' is distinct from case
          when topic like 'chat:%' and not shared_has_id then null
          else expected_message_id end
      )
  ) then
    raise exception 'Unexpected event shape, privacy flag, or deleted ID';
  end if;

  insert into deletion_seen_events
  select id from realtime.messages e
  where payload->>'conversation_id' = '79000000-0000-0000-0000-000000000001'
  on conflict do nothing;
end;
$$;

insert into auth.users(id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('78000000-0000-0000-0000-000000000001', false, false, '{}'),
  ('78000000-0000-0000-0000-000000000002', false, false, '{}'),
  ('78000000-0000-0000-0000-000000000003', false, false, '{}');
insert into public.conversations(id, user_one_id, user_two_id, created_by)
values ('79000000-0000-0000-0000-000000000001',
  '78000000-0000-0000-0000-000000000001',
  '78000000-0000-0000-0000-000000000002',
  '78000000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id, user_id)
values
  ('79000000-0000-0000-0000-000000000001', '78000000-0000-0000-0000-000000000001'),
  ('79000000-0000-0000-0000-000000000001', '78000000-0000-0000-0000-000000000002');
insert into public.messages(id, conversation_id, sender_id, type, text)
select ('7a000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  '79000000-0000-0000-0000-000000000001',
  '78000000-0000-0000-0000-000000000001',
  case when i = 1 then 'image' else 'text' end, 'deletion fixture ' || i
from generate_series(1,6) i;
insert into public.message_attachments(
  id, message_id, position, kind, storage_path, mime_type, size_bytes
) values (
  '7b000000-0000-0000-0000-000000000001',
  '7a000000-0000-0000-0000-000000000001', 0, 'image',
  '79000000-0000-0000-0000-000000000001/78000000-0000-0000-0000-000000000001/7a000000-0000-0000-0000-000000000001/0.jpg',
  'image/jpeg', 100
);
-- Normal inserts still produce only the existing generic payload.
select pg_temp.expect_deletion_events(6, 6, 6, 'insert', null);

select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.soft_delete_message('7a000000-0000-0000-0000-000000000001', true);
reset role;
select pg_temp.expect_deletion_events(1, 1, 1, 'deleted', '7a000000-0000-0000-0000-000000000001');

do $$
begin
  if not exists (
    select 1 from public.messages m join public.message_attachments a on a.message_id = m.id
    where m.id = '7a000000-0000-0000-0000-000000000001'
      and m.deleted_for_everyone_at is not null
      and m.cleanup_after = m.deleted_for_everyone_at + interval '90 days'
      and a.deleted_at = m.deleted_for_everyone_at and a.cleanup_after = m.cleanup_after
  ) then raise exception 'Message/attachment retention changed'; end if;
end;
$$;

-- Two retries in one statement have identical statement_timestamp(). Each
-- actual UPDATE must still produce exactly one exact-ID event per topic.
set local role authenticated;
do $$
begin
  perform public.soft_delete_message('7a000000-0000-0000-0000-000000000001', true);
  perform public.soft_delete_message('7a000000-0000-0000-0000-000000000001', true);
end;
$$;
reset role;
select pg_temp.expect_deletion_events(2, 2, 2, 'deleted', '7a000000-0000-0000-0000-000000000001');

-- An unrelated UPDATE must not cause a tombstone to become a generic refresh.
update public.messages set text = 'still deleted'
where id = '7a000000-0000-0000-0000-000000000001';
select pg_temp.expect_deletion_events(1, 1, 1, 'deleted', '7a000000-0000-0000-0000-000000000001');
update public.messages set text = 'still visible'
where id = '7a000000-0000-0000-0000-000000000005';
select pg_temp.expect_deletion_events(1, 1, 1, 'update', null);

-- Personal hide and retry notify only the user's topic with an exact ID.
set local role authenticated;
select public.soft_delete_message('7a000000-0000-0000-0000-000000000002', false);
select public.soft_delete_message('7a000000-0000-0000-0000-000000000002', false);
reset role;
select pg_temp.expect_deletion_events(2, 0, 2, 'deleted', '7a000000-0000-0000-0000-000000000002', false);

-- Preserve the existing non-author and NULL-flag fallback to personal hiding.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.soft_delete_message('7a000000-0000-0000-0000-000000000003', true);
reset role;
select pg_temp.expect_deletion_events(0, 1, 1, 'deleted', '7a000000-0000-0000-0000-000000000003', false);
set local role authenticated;
select public.soft_delete_message('7a000000-0000-0000-0000-000000000004', null);
reset role;
select pg_temp.expect_deletion_events(0, 1, 1, 'deleted', '7a000000-0000-0000-0000-000000000004', false);
do $$
begin
  if exists (select 1 from public.messages
    where id in ('7a000000-0000-0000-0000-000000000003', '7a000000-0000-0000-0000-000000000004')
      and deleted_for_everyone_at is not null
  ) then raise exception 'Non-author or NULL flag deleted globally'; end if;
  if (select count(*) from public.message_hidden_for_users
    where user_id = '78000000-0000-0000-0000-000000000002'
      and message_id in ('7a000000-0000-0000-0000-000000000003', '7a000000-0000-0000-0000-000000000004')
  ) <> 2 then raise exception 'Personal fallback not stored'; end if;
  if exists (select 1 from realtime.messages
    where topic = 'user:78000000-0000-0000-0000-000000000001:chats'
      and payload->>'message_id' in ('7a000000-0000-0000-0000-000000000003', '7a000000-0000-0000-0000-000000000004')
  ) then raise exception 'Personal fallback leaked to peer'; end if;
  if (select count(*) from realtime.messages
    where topic = 'user:78000000-0000-0000-0000-000000000002:chats'
      and payload->>'reason' = 'deleted'
      and payload->>'message_id' in ('7a000000-0000-0000-0000-000000000003', '7a000000-0000-0000-0000-000000000004')
  ) <> 2 then raise exception 'Personal fallback events missing or duplicated'; end if;
end;
$$;
-- An aborted operation must roll back both data and its broadcast records.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$
begin
  begin
    perform public.soft_delete_message('7a000000-0000-0000-0000-000000000006', true);
    raise exception using errcode = 'ZX001', message = 'test rollback';
  exception when sqlstate 'ZX001' then null;
  end;
end;
$$;
reset role;
select pg_temp.expect_deletion_events(0, 0, 0, 'deleted', null);
do $$
begin
  if exists (select 1 from public.messages
    where id = '7a000000-0000-0000-0000-000000000006' and deleted_for_everyone_at is not null
  ) then raise exception 'Aborted deletion changed the message'; end if;
end;
$$;

-- Unknown messages, non-members and absent identity cannot delete or publish.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $$
declare target_id uuid;
begin
  foreach target_id in array array[
    '7a000000-0000-0000-0000-000000000006'::uuid,
    '7a000000-0000-0000-0000-000000000099'::uuid
  ] loop
    begin
      perform public.soft_delete_message(target_id, true);
      raise exception using errcode = 'ZX002', message = 'Unauthorized delete succeeded';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'message_access_denied' then raise; end if;
    end;
  end loop;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$
begin
  begin
    perform public.soft_delete_message('7a000000-0000-0000-0000-000000000006', false);
    raise exception using errcode = 'ZX002', message = 'Missing identity delete succeeded';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'message_access_denied' then raise; end if;
  end;
end;
$$;
reset role;
select pg_temp.expect_deletion_events(0, 0, 0, 'deleted', null);

do $$
begin
  if has_function_privilege('anon', 'public.soft_delete_message(uuid,boolean)', 'execute')
    or has_function_privilege('anon', 'private.soft_delete_message_impl(uuid,boolean)', 'execute')
    or has_function_privilege('authenticated', 'private.broadcast_conversation_change_impl()', 'execute')
    or not has_function_privilege('authenticated', 'public.soft_delete_message(uuid,boolean)', 'execute')
  then raise exception 'Deletion function privileges changed'; end if;
end;
$$;

rollback;
