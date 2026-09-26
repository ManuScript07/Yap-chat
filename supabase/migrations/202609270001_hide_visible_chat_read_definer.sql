-- Keep the existing Data API RPC, but do not expose its elevated implementation.
-- Preserve the function object (and therefore its behavior) across the move.
alter function public.mark_visible_conversation_messages_read(uuid, uuid[])
  set schema private;
alter function private.mark_visible_conversation_messages_read(uuid, uuid[])
  rename to mark_visible_conversation_messages_read_impl;

revoke all on function private.mark_visible_conversation_messages_read_impl(uuid, uuid[])
  from public, anon;
grant execute on function private.mark_visible_conversation_messages_read_impl(uuid, uuid[])
  to authenticated;

create function public.mark_visible_conversation_messages_read(
  target_conversation_id uuid,
  visible_message_ids uuid[]
)
returns integer
language sql security invoker set search_path = ''
as $$
  select private.mark_visible_conversation_messages_read_impl(
    target_conversation_id, visible_message_ids
  );
$$;

revoke all on function public.mark_visible_conversation_messages_read(uuid, uuid[])
  from public, anon;
grant execute on function public.mark_visible_conversation_messages_read(uuid, uuid[])
  to authenticated;
