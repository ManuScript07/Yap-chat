-- Run only against a disposable local Supabase database. Rolls back fixtures.
begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('51000000-0000-0000-0000-000000000001', false, false, '{}'::jsonb),
  ('51000000-0000-0000-0000-000000000002', false, false, '{}'::jsonb),
  ('51000000-0000-0000-0000-000000000003', false, false, '{}'::jsonb);

insert into public.conversations (id, user_one_id, user_two_id, created_by)
values (
  '52000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000001'
);

insert into public.conversation_members (conversation_id, user_id)
values
  ('52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002');

insert into public.messages (id, conversation_id, sender_id, type, text, created_at)
select
  ('53000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  '52000000-0000-0000-0000-000000000001'::uuid,
  '51000000-0000-0000-0000-000000000001'::uuid,
  'text', i::text,
  '2026-01-01 00:00:00+00'::timestamptz + i * interval '1 second'
from generate_series(1, 140) i;

insert into public.message_hidden_for_users (message_id, user_id)
values (
  '53000000-0000-0000-0000-000000000069',
  '51000000-0000-0000-0000-000000000001'
);

select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  conversation uuid := '52000000-0000-0000-0000-000000000001';
  target uuid := '53000000-0000-0000-0000-000000000070';
  ids uuid[];
  older_count integer;
begin
  select array_agg(id order by created_at desc, id desc) into ids
  from public.get_conversation_message_window(conversation, target);
  if array_length(ids, 1) <> 60 or ids[31] <> target then
    raise exception 'Window must contain 30 newer messages, target, and 29 visible older messages';
  end if;
  if '53000000-0000-0000-0000-000000000069'::uuid = any(ids) then
    raise exception 'Locally hidden message leaked into target window';
  end if;

  select count(*) into older_count
  from public.get_conversation_messages(
    conversation, '2026-01-01 00:01:11+00', target, 60);
  if older_count <> 60 then
    raise exception 'Original older-message pagination regressed';
  end if;

  select array_agg(id order by created_at desc, id desc) into ids
  from public.get_conversation_message_window(
    conversation, null, '2026-01-01 00:01:10+00', target);
  if array_length(ids, 1) <> 60 or ids[1] <> '53000000-0000-0000-0000-000000000130'::uuid
      or ids[60] <> '53000000-0000-0000-0000-000000000071'::uuid then
    raise exception 'Newer page must be bounded and contiguous';
  end if;

  if exists (
    select 1 from public.get_conversation_message_window(
      conversation, '53000000-0000-0000-0000-000000000069')) then
    raise exception 'A hidden target must not be navigable';
  end if;
end;
$$;

reset role;
update public.messages
set deleted_for_everyone_at = statement_timestamp()
where id = '53000000-0000-0000-0000-000000000070';

select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$
begin
  if exists (
    select 1 from public.get_conversation_message_window(
      '52000000-0000-0000-0000-000000000001',
      '53000000-0000-0000-0000-000000000070')) then
    raise exception 'A deleted target must not be navigable';
  end if;
end;
$$;

reset role;
update public.conversation_members
set cleared_at = '2026-01-01 00:01:40+00'
where conversation_id = '52000000-0000-0000-0000-000000000001'
  and user_id = '51000000-0000-0000-0000-000000000001';

set local role authenticated;
do $$
begin
  if exists (
    select 1 from public.get_conversation_message_window(
      '52000000-0000-0000-0000-000000000001',
      '53000000-0000-0000-0000-000000000080')) then
    raise exception 'A cleared target must not be navigable';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims',
  '{"sub":"51000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if exists (
    select 1 from public.get_conversation_message_window(
      '52000000-0000-0000-0000-000000000001',
      '53000000-0000-0000-0000-000000000070')) then
    raise exception 'A non-member obtained conversation messages';
  end if;
end;
$$;

rollback;
