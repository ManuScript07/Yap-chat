-- Disposable local DB contract test. All fixture rows and broadcasts roll back.
begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('54000000-0000-0000-0000-000000000001', false, false, '{}'::jsonb),
  ('54000000-0000-0000-0000-000000000002', false, false, '{}'::jsonb);

insert into public.conversations (id, user_one_id, user_two_id, created_by)
values (
  '55000000-0000-0000-0000-000000000001',
  '54000000-0000-0000-0000-000000000001',
  '54000000-0000-0000-0000-000000000002',
  '54000000-0000-0000-0000-000000000001'
);
insert into public.conversation_members (conversation_id, user_id)
values
  ('55000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001'),
  ('55000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000002');

insert into public.messages (id, conversation_id, sender_id, type, text)
values (
  '56000000-0000-0000-0000-000000000001',
  '55000000-0000-0000-0000-000000000001',
  '54000000-0000-0000-0000-000000000001',
  'text', 'focused-message'
);

update public.messages
set deleted_for_everyone_at = statement_timestamp()
where id = '56000000-0000-0000-0000-000000000001';

insert into public.messages (id, conversation_id, sender_id, type, text)
values (
  '56000000-0000-0000-0000-000000000002',
  '55000000-0000-0000-0000-000000000001',
  '54000000-0000-0000-0000-000000000001',
  'text', 'hidden-message'
);
select set_config(
  'request.jwt.claim.sub', '54000000-0000-0000-0000-000000000001', true
);
select private.soft_delete_message_impl(
  '56000000-0000-0000-0000-000000000002', false
);

do $$
declare
  target_id text := '56000000-0000-0000-0000-000000000001';
  conversation_id text := '55000000-0000-0000-0000-000000000001';
begin
  if not exists (
    select 1 from realtime.messages
    where topic = 'user:54000000-0000-0000-0000-000000000002:chats'
      and event = 'changed'
      and payload->>'conversation_id' = conversation_id
      and payload->>'reason' = 'deleted'
      and payload->>'message_id' = target_id
  ) then
    raise exception 'Peer did not receive the deleted message id';
  end if;
  if not exists (
    select 1 from realtime.messages
    where topic = 'user:54000000-0000-0000-0000-000000000001:chats'
      and payload->>'reason' = 'deleted'
      and payload->>'message_id' = target_id
  ) then
    raise exception 'Sender did not receive the deleted message id';
  end if;
  if exists (
    select 1 from realtime.messages
    where topic = 'user:54000000-0000-0000-0000-000000000002:chats'
      and payload->>'reason' = 'insert'
      and payload ? 'message_id'
  ) then
    raise exception 'Normal insert unexpectedly exposes a message id';
  end if;
  if not exists (
    select 1 from realtime.messages
    where topic = 'user:54000000-0000-0000-0000-000000000001:chats'
      and payload->>'reason' = 'deleted'
      and payload->>'message_id' = '56000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Per-user hide did not identify the hidden message';
  end if;
  if exists (
    select 1 from realtime.messages
    where topic = 'user:54000000-0000-0000-0000-000000000002:chats'
      and payload->>'message_id' = '56000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Per-user hide leaked to the other member';
  end if;
end;
$$;

rollback;
