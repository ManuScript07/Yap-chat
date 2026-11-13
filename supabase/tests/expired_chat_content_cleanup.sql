-- Contract test for the 90-day server-side chat cleanup.  It uses already
-- expired fixture timestamps so it is safe to run on a disposable local DB.

begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('40000000-0000-0000-0000-000000000001', false, false, '{}'::jsonb),
  ('40000000-0000-0000-0000-000000000002', false, false, '{}'::jsonb),
  ('40000000-0000-0000-0000-000000000003', false, false, '{}'::jsonb),
  ('40000000-0000-0000-0000-000000000004', false, false, '{}'::jsonb),
  ('40000000-0000-0000-0000-000000000005', false, false, '{}'::jsonb),
  ('40000000-0000-0000-0000-000000000006', false, false, '{}'::jsonb);

insert into public.conversations (id, user_one_id, user_two_id, created_by)
values
  (
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000001'
  ),
  (
    '41000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000003'
  ),
  (
    '41000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000005',
    '40000000-0000-0000-0000-000000000006',
    '40000000-0000-0000-0000-000000000005'
  );

insert into public.conversation_members (conversation_id, user_id, hidden_at)
values
  ('41000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', null),
  ('41000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002', null),
  ('41000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', statement_timestamp() - interval '91 days'),
  ('41000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000004', statement_timestamp() - interval '90 days 1 second'),
  ('41000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000005', statement_timestamp() - interval '91 days'),
  ('41000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000006', null);

insert into public.friendships (user_one_id, user_two_id)
values (
  '40000000-0000-0000-0000-000000000003',
  '40000000-0000-0000-0000-000000000004'
);

insert into public.messages (
  id, conversation_id, sender_id, type, text,
  deleted_for_everyone_at, cleanup_after
)
values
  (
    '42000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'image', '', statement_timestamp() - interval '91 days',
    statement_timestamp() - interval '1 second'
  ),
  (
    '42000000-0000-0000-0000-000000000002',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000002',
    'text', 'reply', null, null
  ),
  (
    '42000000-0000-0000-0000-000000000003',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'audio', '', null, null
  ),
  (
    '42000000-0000-0000-0000-000000000004',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'text', 'hidden only for one participant', null, null
  ),
  (
    '42000000-0000-0000-0000-000000000006',
    '41000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000005',
    'image', '', null, null
  ),
  (
    '42000000-0000-0000-0000-000000000007',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'text', 'new retention deadline', null, null
  ),
  (
    '42000000-0000-0000-0000-000000000008',
    '41000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000002',
    'text', 'new local-hide deadline', null, null
  );

update public.messages
set reply_to_message_id = '42000000-0000-0000-0000-000000000001'
where id = '42000000-0000-0000-0000-000000000002';

insert into public.message_attachments (
  id, message_id, position, kind, storage_path, mime_type, size_bytes
)
values
  (
    '43000000-0000-0000-0000-000000000001',
    '42000000-0000-0000-0000-000000000001', 0, 'image',
    '41000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/42000000-0000-0000-0000-000000000001/0.jpg',
    'image/jpeg', 100
  ),
  (
    '43000000-0000-0000-0000-000000000002',
    '42000000-0000-0000-0000-000000000003', 0, 'audio',
    '41000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001/42000000-0000-0000-0000-000000000003/0.m4a',
    'audio/mp4', 100
  ),
  (
    '43000000-0000-0000-0000-000000000004',
    '42000000-0000-0000-0000-000000000006', 0, 'image',
    '41000000-0000-0000-0000-000000000003/40000000-0000-0000-0000-000000000005/42000000-0000-0000-0000-000000000006/0.jpg',
    'image/jpeg', 100
  );

insert into public.message_hidden_for_users (message_id, user_id, hidden_at, cleanup_after)
values
  (
    '42000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000001',
    statement_timestamp() - interval '91 days', statement_timestamp() - interval '1 second'
  ),
  (
    '42000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000002',
    statement_timestamp() - interval '90 days 1 second', statement_timestamp() - interval '1 second'
  ),
  (
    '42000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000001',
    statement_timestamp() - interval '91 days', statement_timestamp() - interval '1 second'
  );

select set_config(
  'request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select public.soft_delete_message(
  '42000000-0000-0000-0000-000000000007', true
);
select public.soft_delete_message(
  '42000000-0000-0000-0000-000000000008', false
);
reset role;

select private.finalize_expired_chat_content(200, 50);

do $$
declare
  queued_count integer;
  claimed_count integer;
begin
  if exists (
    select 1 from public.messages
    where id in (
      '42000000-0000-0000-0000-000000000001',
      '42000000-0000-0000-0000-000000000003'
    )
  ) then
    raise exception 'Expired recalled or both-hidden messages remained';
  end if;

  if not exists (
    select 1 from public.messages
    where id = '42000000-0000-0000-0000-000000000004'
  ) then
    raise exception 'Message hidden by only one participant was deleted';
  end if;

  if exists (
    select 1 from public.messages
    where id = '42000000-0000-0000-0000-000000000002'
      and reply_to_message_id is not null
  ) then
    raise exception 'Reply link to permanently deleted message was not cleared';
  end if;

  if not exists (
    select 1 from public.messages
    where id = '42000000-0000-0000-0000-000000000007'
      and cleanup_after = deleted_for_everyone_at + interval '90 days'
  ) then
    raise exception 'New global deletion did not receive an exact 90-day deadline';
  end if;

  if not exists (
    select 1
    from public.message_hidden_for_users
    where message_id = '42000000-0000-0000-0000-000000000008'
      and user_id = '40000000-0000-0000-0000-000000000001'
      and cleanup_after = hidden_at + interval '90 days'
  ) then
    raise exception 'New local hide did not receive an exact 90-day deadline';
  end if;

  if exists (
    select 1 from public.conversations
    where id = '41000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Conversation hidden by both participants was not deleted';
  end if;

  if not exists (
    select 1 from public.conversations
    where id = '41000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'Conversation hidden by one participant was deleted';
  end if;

  if not exists (
    select 1 from public.friendships
    where user_one_id = '40000000-0000-0000-0000-000000000003'
      and user_two_id = '40000000-0000-0000-0000-000000000004'
  ) then
    raise exception 'Chat cleanup unexpectedly removed friendship';
  end if;

  select count(*) into queued_count
  from private.chat_media_cleanup_queue
  where deleted_at is null;
  if queued_count <> 2 then
    raise exception 'Expected 2 queued media objects, got %', queued_count;
  end if;

  select count(*) into claimed_count
  from private.claim_chat_media_cleanup_batch(1000);
  if claimed_count <> 2 then
    raise exception 'Expected to claim all queued media objects, got %', claimed_count;
  end if;
end;
$$;

rollback;
