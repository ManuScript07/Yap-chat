-- Reuse the existing user-addressed conversation broadcast. A focused,
-- non-contiguous history window needs the exact deleted id to discard its
-- snapshot without re-fetching every message after each chat event.
create or replace function private.broadcast_conversation_change_impl()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_conversation_id uuid := new.conversation_id;
  change_payload jsonb;
  member record;
begin
  if tg_op = 'INSERT' then
    update public.conversation_members
    set hidden_at = null
    where conversation_id = target_conversation_id;

    update public.conversations
    set last_message_id = new.id, updated_at = new.created_at
    where id = target_conversation_id;
  end if;

  change_payload := jsonb_build_object(
    'conversation_id', target_conversation_id, 'reason', lower(tg_op)
  );
  if tg_op = 'UPDATE' then
    if old.deleted_for_everyone_at is null
        and new.deleted_for_everyone_at is not null then
      change_payload := jsonb_build_object(
        'conversation_id', target_conversation_id,
        'reason', 'deleted',
        'message_id', new.id
      );
    end if;
  end if;

  perform realtime.send(
    change_payload, 'changed', 'chat:' || target_conversation_id::text, true
  );
  for member in
    select user_id from public.conversation_members
    where conversation_id = target_conversation_id
  loop
    perform realtime.send(
      change_payload, 'changed', 'user:' || member.user_id::text || ':chats', true
    );
  end loop;
  return new;
end;
$$;

-- The per-user hide does not UPDATE public.messages, so the trigger above
-- cannot identify it. Add the id only to the existing user-addressed event;
-- the shared chat topic keeps its previous generic payload.
create or replace function private.soft_delete_message_impl(
  target_message_id uuid,
  delete_for_everyone boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  target_message public.messages%rowtype;
  deletion_timestamp timestamptz := statement_timestamp();
begin
  select * into target_message
  from public.messages
  where id = target_message_id;

  if target_message.id is null or not public.is_conversation_member(
    target_message.conversation_id,
    current_user_id
  ) then
    raise exception 'message_access_denied';
  end if;

  if delete_for_everyone and target_message.sender_id = current_user_id then
    update public.messages
    set deleted_for_everyone_at = deletion_timestamp,
        cleanup_after = deletion_timestamp + interval '90 days'
    where id = target_message_id;

    update public.message_attachments
    set deleted_at = deletion_timestamp,
        cleanup_after = deletion_timestamp + interval '90 days'
    where message_id = target_message_id;
  else
    insert into public.message_hidden_for_users (message_id, user_id)
    values (target_message_id, current_user_id)
    on conflict (message_id, user_id) do nothing;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted'
    ),
    'changed',
    'chat:' || target_message.conversation_id::text,
    true
  );

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted',
      'message_id', target_message_id
    ),
    'changed',
    'user:' || current_user_id::text || ':chats',
    true
  );
end;
$$;
