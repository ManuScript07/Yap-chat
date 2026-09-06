-- Restore the RLS-safe peer lookup after the write-quota wrapper. The
-- conversation_members table is intentionally not directly readable through a
-- SECURITY INVOKER public function, so the existing narrow private helper must
-- be used to resolve the peer.

create or replace function public.send_chat_message(
  message_id uuid,
  target_conversation_id uuid,
  message_type text,
  message_text text default '',
  message_latitude double precision default null,
  message_longitude double precision default null,
  reply_message_id uuid default null,
  message_attachments jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  -- Network retries reuse the message id. Their already committed result must
  -- remain idempotent and must not consume a second write-quota slot.
  if exists (
    select 1
    from public.messages message
    where message.id = message_id
      and message.conversation_id = target_conversation_id
      and message.sender_id = auth.uid()
  ) then
    return message_id;
  end if;

  perform private.consume_chat_message_write_quota();

  peer_user_id := private.get_direct_conversation_peer_impl(
    target_conversation_id
  );
  if peer_user_id is null
     or private.is_account_globally_banned(peer_user_id)
     or private.is_conversation_blocked_impl(target_conversation_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;

  return private.send_chat_message_impl(
    message_id, target_conversation_id, message_type, message_text,
    message_latitude, message_longitude, reply_message_id, message_attachments
  );
end;
$$;

revoke all on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
to authenticated, service_role;

notify pgrst, 'reload schema';
