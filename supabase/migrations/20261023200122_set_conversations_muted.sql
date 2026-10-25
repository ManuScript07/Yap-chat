-- Explicit, retry-safe setting for new clients. Keep the legacy toggle RPC
-- unchanged so already installed versions retain their existing contract.
create or replace function private.set_conversations_muted_impl(
  conversation_ids uuid[], muted boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  changed_ids uuid[];
begin
  if actor is null then raise exception 'authentication_required'; end if;
  perform private.require_active_account();
  if muted is null then
    raise exception using errcode = '22023', message = 'invalid_chat_mute_state';
  end if;
  if coalesce(cardinality(conversation_ids), 0) not between 1 and 50
     or array_ndims(conversation_ids) <> 1
     or array_position(conversation_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;

  -- Shared quota with the legacy endpoint: alternating APIs cannot double it.
  -- No-op requests still consume quota, but never write rows or broadcast.
  perform private.consume_chat_bulk_action_write_quota('mute');
  with changed as (
    update public.conversation_members cm
    set is_muted = muted
    where cm.user_id = actor
      and cm.conversation_id = any(conversation_ids)
      and cm.is_muted is distinct from muted
    returning cm.conversation_id
  )
  select array_agg(conversation_id order by conversation_id)
    into changed_ids from changed;

  if cardinality(changed_ids) > 0 then
    perform realtime.send(
      jsonb_build_object('conversation_ids', changed_ids, 'reason', 'muted'),
      'changed', 'user:' || actor::text || ':chats', true
    );
  end if;
end;
$$;

create or replace function public.set_conversations_muted(
  conversation_ids uuid[], muted boolean
)
returns void language sql security invoker set search_path = ''
as $$
  select private.set_conversations_muted_impl(conversation_ids, muted);
$$;

revoke all on function private.set_conversations_muted_impl(uuid[], boolean)
  from public, anon;
revoke all on function public.set_conversations_muted(uuid[], boolean)
  from public, anon;
grant execute on function private.set_conversations_muted_impl(uuid[], boolean)
  to authenticated, service_role;
grant execute on function public.set_conversations_muted(uuid[], boolean)
  to authenticated, service_role;

notify pgrst, 'reload schema';
