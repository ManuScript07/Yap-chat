-- Reading an open conversation is different from the explicit "mark whole
-- conversation read" action in the chat list. The client submits only rows
-- actually visible in the current viewport, never a conversation-wide cursor.
create table private.visible_chat_read_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on private.visible_chat_read_limits from public, anon, authenticated;

create function public.mark_visible_conversation_messages_read(
  target_conversation_id uuid,
  visible_message_ids uuid[]
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  clear_boundary timestamptz;
  read_timestamp timestamptz := statement_timestamp();
  current_count integer;
  inserted_count integer;
  member_id uuid;
begin
  if actor_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if target_conversation_id is null or visible_message_ids is null
      or cardinality(visible_message_ids) < 1
      or cardinality(visible_message_ids) > 60
      or array_position(visible_message_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_visible_messages';
  end if;

  select cm.cleared_at into clear_boundary
  from public.conversation_members cm
  where cm.conversation_id = target_conversation_id and cm.user_id = actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'conversation_not_available';
  end if;

  insert into private.visible_chat_read_limits as limits (
    user_id, window_started_at, request_count
  ) values (actor_id, read_timestamp, 1)
  on conflict (user_id) do update set
    window_started_at = case
      when limits.window_started_at <= read_timestamp - interval '1 minute'
        then read_timestamp else limits.window_started_at end,
    request_count = case
      when limits.window_started_at <= read_timestamp - interval '1 minute'
        then 1 else limits.request_count + 1 end
  returning request_count into current_count;
  if current_count > 60 then
    raise exception using errcode = 'P0001', message = 'visible_chat_read_rate_limited';
  end if;

  with inserted as (
    insert into public.message_receipts (message_id, user_id, read_at)
    select distinct message.id, actor_id, read_timestamp
    from unnest(visible_message_ids) as requested(id)
    join public.messages message on message.id = requested.id
    where message.conversation_id = target_conversation_id
      and message.sender_id <> actor_id
      and message.created_at > coalesce(clear_boundary, '-infinity'::timestamptz)
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = actor_id
      )
    on conflict (message_id, user_id) do nothing
    returning message_id
  ) select count(*) into inserted_count from inserted;

  if inserted_count > 0 then
    update public.conversation_members
    set last_read_at = read_timestamp
    where conversation_id = target_conversation_id and user_id = actor_id;

    for member_id in
      select cm.user_id from public.conversation_members cm
      where cm.conversation_id = target_conversation_id
    loop
      perform realtime.send(
        jsonb_build_object('conversation_id', target_conversation_id, 'reason', 'read'),
        'changed', 'user:' || member_id::text || ':chats', true
      );
    end loop;
  end if;
  return inserted_count;
end;
$$;

revoke all on function public.mark_visible_conversation_messages_read(uuid, uuid[])
  from public, anon;
grant execute on function public.mark_visible_conversation_messages_read(uuid, uuid[])
  to authenticated;
