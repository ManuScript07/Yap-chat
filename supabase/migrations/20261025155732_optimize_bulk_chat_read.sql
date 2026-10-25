-- Keep the installed clients' void RPC. Manual whole-chat reading remains
-- separate from viewport reading: last_read_at is not a contiguous cursor.
create or replace function private.mark_conversations_read_impl(conversation_ids uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  read_timestamp timestamptz := statement_timestamp();
  changed_ids uuid[] := array[]::uuid[];
  target_id uuid;
  clear_boundary timestamptz;
  inserted_count integer;
  has_existing_receipts boolean;
  member record;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  perform private.require_active_account();
  if coalesce(cardinality(conversation_ids), 0) not between 1 and 50
     or array_ndims(conversation_ids) <> 1
     or array_position(conversation_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;

  -- First reading on an account needs no anti-join: there cannot be an old
  -- receipt to exclude. ON CONFLICT still handles a concurrent reader.
  select exists(select 1 from public.message_receipts where user_id=actor)
    into has_existing_receipts;

  -- Bind each conversation as an index boundary. A single broad join over all
  -- histories costs more on large caches and is unnecessary for a <=50 batch.
  for target_id in select distinct id from unnest(conversation_ids) requested(id) order by id
  loop
    select cm.cleared_at into clear_boundary from public.conversation_members cm
    where cm.user_id = actor and cm.conversation_id = target_id;
    if not found then continue; end if;

    if not has_existing_receipts then
      insert into public.message_receipts (message_id, user_id, read_at)
      select message.id, actor, read_timestamp from public.messages message
      where message.conversation_id = target_id and message.sender_id <> actor
        and message.deleted_for_everyone_at is null
        and message.created_at > coalesce(clear_boundary, '-infinity'::timestamptz)
        and not exists (
          select 1 from public.message_hidden_for_users hidden
          where hidden.message_id = message.id and hidden.user_id = actor
        )
      order by message.id
      on conflict (message_id, user_id) do nothing;
    else
      insert into public.message_receipts (message_id, user_id, read_at)
      select message.id, actor, read_timestamp
      from public.messages message
      where message.conversation_id = target_id and message.sender_id <> actor
        and message.deleted_for_everyone_at is null
        and message.created_at > coalesce(clear_boundary, '-infinity'::timestamptz)
        and not exists (
          select 1 from public.message_hidden_for_users hidden
          where hidden.message_id = message.id and hidden.user_id = actor
        )
        and not exists (
          select 1 from public.message_receipts receipt
          where receipt.message_id = message.id and receipt.user_id = actor
        )
      -- Consistent conflict-lock order for overlapping batches/devices.
      order by message.id
      on conflict (message_id, user_id) do nothing;
    end if;
    get diagnostics inserted_count = row_count;
    if inserted_count > 0 then changed_ids := array_append(changed_ids, target_id); end if;
  end loop;

  if coalesce(cardinality(changed_ids), 0) = 0 then return; end if;

  update public.conversation_members cm
  set last_read_at = greatest(cm.last_read_at, read_timestamp)
  where cm.user_id = actor and cm.conversation_id = any(changed_ids);

  -- Existing event shape and transport; never one broadcast per receipt.
  for member in
    select cm.conversation_id, cm.user_id from public.conversation_members cm
    where cm.conversation_id = any(changed_ids)
    order by cm.conversation_id, cm.user_id
  loop
    perform realtime.send(
      jsonb_build_object('conversation_id', member.conversation_id, 'reason', 'read'),
      'changed', 'user:' || member.user_id::text || ':chats', true
    );
  end loop;
end;
$$;

create or replace function public.mark_conversations_read(conversation_ids uuid[])
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if coalesce(cardinality(conversation_ids), 0) not between 1 and 50
     or array_ndims(conversation_ids) <> 1
     or array_position(conversation_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;
  perform private.consume_chat_bulk_action_write_quota('mark_read');
  perform private.mark_conversations_read_impl(conversation_ids);
end;
$$;

revoke all on function private.mark_conversations_read_impl(uuid[]) from public, anon;
revoke all on function public.mark_conversations_read(uuid[]) from public, anon;
grant execute on function private.mark_conversations_read_impl(uuid[]) to authenticated, service_role;
grant execute on function public.mark_conversations_read(uuid[]) to authenticated, service_role;
notify pgrst, 'reload schema';
