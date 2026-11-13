-- Run only against disposable local Supabase; all fixtures roll back.
begin;

-- The API entry point must not run with the function owner's privileges.
do $$
begin
  if (select p.prosecdef from pg_proc p
      where p.oid = 'public.mark_visible_conversation_messages_read(uuid,uuid[])'::regprocedure) then
    raise exception 'Exposed visible-read RPC is still SECURITY DEFINER';
  end if;
  if not (select p.prosecdef from pg_proc p
      where p.oid = 'private.mark_visible_conversation_messages_read_impl(uuid,uuid[])'::regprocedure) then
    raise exception 'Private visible-read implementation lost SECURITY DEFINER';
  end if;
  if has_function_privilege('anon',
      'public.mark_visible_conversation_messages_read(uuid,uuid[])', 'EXECUTE')
      or has_function_privilege('anon',
      'private.mark_visible_conversation_messages_read_impl(uuid,uuid[])', 'EXECUTE')
      or not has_function_privilege('authenticated',
      'public.mark_visible_conversation_messages_read(uuid,uuid[])', 'EXECUTE') then
    raise exception 'Visible-read function grants are incorrect';
  end if;
end $$;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('57000000-0000-0000-0000-000000000001', false, false, '{}'::jsonb),
  ('57000000-0000-0000-0000-000000000002', false, false, '{}'::jsonb),
  ('57000000-0000-0000-0000-000000000003', false, false, '{}'::jsonb);

insert into public.conversations (id, user_one_id, user_two_id, created_by)
values
  ('58000000-0000-0000-0000-000000000001',
    '57000000-0000-0000-0000-000000000001',
    '57000000-0000-0000-0000-000000000002',
    '57000000-0000-0000-0000-000000000001'),
  ('58000000-0000-0000-0000-000000000002',
    '57000000-0000-0000-0000-000000000001',
    '57000000-0000-0000-0000-000000000003',
    '57000000-0000-0000-0000-000000000001');
insert into public.conversation_members (conversation_id, user_id)
values
  ('58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001'),
  ('58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000002'),
  ('58000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000001'),
  ('58000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000003');

insert into public.messages (id, conversation_id, sender_id, type, text)
values
  ('59000000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001', 'text', 'visible'),
  ('59000000-0000-0000-0000-000000000002', '58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001', 'text', 'invisible'),
  ('59000000-0000-0000-0000-000000000003', '58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000002', 'text', 'mine'),
  ('59000000-0000-0000-0000-000000000004', '58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001', 'text', 'deleted'),
  ('59000000-0000-0000-0000-000000000005', '58000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000001', 'text', 'other conversation');
update public.messages set deleted_for_everyone_at = now()
where id = '59000000-0000-0000-0000-000000000004';

select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000002', true);
set local role authenticated;
do $$
declare inserted integer;
begin
  select public.mark_visible_conversation_messages_read(
    '58000000-0000-0000-0000-000000000001',
    array[
      '59000000-0000-0000-0000-000000000001',
      '59000000-0000-0000-0000-000000000003',
      '59000000-0000-0000-0000-000000000004',
      '59000000-0000-0000-0000-000000000005'
    ]::uuid[]
  ) into inserted;
  if inserted <> 1 then raise exception 'Expected only visible incoming message'; end if;
  if public.mark_visible_conversation_messages_read(
    '58000000-0000-0000-0000-000000000001',
    array['59000000-0000-0000-0000-000000000001']::uuid[]
  ) <> 0 then raise exception 'Repeated read must be idempotent'; end if;
end $$;
reset role;

-- A cleared or locally hidden message must not be marked by this RPC.
update public.conversation_members set cleared_at = statement_timestamp()
where conversation_id = '58000000-0000-0000-0000-000000000001'
  and user_id = '57000000-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
  if public.mark_visible_conversation_messages_read(
    '58000000-0000-0000-0000-000000000001',
    array['59000000-0000-0000-0000-000000000002']::uuid[]
  ) <> 0 then raise exception 'Cleared message was marked read'; end if;
  begin
    perform public.mark_visible_conversation_messages_read(
      '58000000-0000-0000-0000-000000000001',
      array_fill('59000000-0000-0000-0000-000000000002'::uuid, array[61])
    );
    raise exception 'Oversized visible message selection succeeded';
  exception when invalid_parameter_value then null;
  end;
end $$;
reset role;
update public.conversation_members set cleared_at = null
where conversation_id = '58000000-0000-0000-0000-000000000001'
  and user_id = '57000000-0000-0000-0000-000000000002';

insert into public.message_hidden_for_users (message_id, user_id) values
  ('59000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000002');
set local role authenticated;
do $$
begin
  if public.mark_visible_conversation_messages_read(
    '58000000-0000-0000-0000-000000000001',
    array['59000000-0000-0000-0000-000000000002']::uuid[]
  ) <> 0 then raise exception 'Locally hidden message was marked read'; end if;
end $$;
reset role;
delete from public.message_hidden_for_users
where message_id = '59000000-0000-0000-0000-000000000002'
  and user_id = '57000000-0000-0000-0000-000000000002';

do $$
begin
  if (select count(*) from public.message_receipts
      where user_id = '57000000-0000-0000-0000-000000000002') <> 1 then
    raise exception 'Invisible, own or deleted message was marked read';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $$
begin
  begin
    perform public.mark_visible_conversation_messages_read(
      '58000000-0000-0000-0000-000000000001',
      array['59000000-0000-0000-0000-000000000001']::uuid[]
    );
    raise exception 'Non-member read succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- The separate user-initiated bulk action must continue to read the rest.
select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.mark_conversations_read(
  array['58000000-0000-0000-0000-000000000001']::uuid[]
);
reset role;
do $$
begin
  if not exists (
    select 1 from public.message_receipts
    where message_id = '59000000-0000-0000-0000-000000000002'
      and user_id = '57000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Manual whole-chat mark no longer reads hidden viewport rows';
  end if;
end $$;

rollback;
