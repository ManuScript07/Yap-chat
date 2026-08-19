drop function if exists public.hide_conversations(uuid[]);

create or replace function public.hide_conversations(
  conversation_ids uuid[],
  cleared_before timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members member
  set
    cleared_at = greatest(
      coalesce(member.cleared_at, '-infinity'::timestamptz),
      cleared_before
    ),
    hidden_at = case
      when exists (
        select 1
        from public.messages message
        where message.conversation_id = member.conversation_id
          and message.deleted_for_everyone_at is null
          and message.created_at > greatest(
            coalesce(member.cleared_at, '-infinity'::timestamptz),
            cleared_before
          )
      ) then null
      else now()
    end
  where member.user_id = auth.uid()
    and member.conversation_id = any(conversation_ids);

  perform realtime.send(
    jsonb_build_object('conversation_ids', conversation_ids, 'reason', 'hidden'),
    'changed',
    'user:' || auth.uid()::text || ':chats',
    true
  );
end;
$$;

create or replace function public.get_conversation_messages(
  target_conversation_id uuid,
  before_created_at timestamptz default null,
  before_message_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  type text,
  text text,
  latitude double precision,
  longitude double precision,
  reply_to_message_id uuid,
  created_at timestamptz,
  read_at timestamptz,
  attachments jsonb,
  reply_sender_id uuid,
  reply_type text,
  reply_text text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    message.id,
    message.conversation_id,
    message.sender_id,
    message.type,
    message.text,
    message.latitude,
    message.longitude,
    message.reply_to_message_id,
    message.created_at,
    (
      select min(receipt.read_at)
      from public.message_receipts receipt
      where receipt.message_id = message.id
        and receipt.user_id <> message.sender_id
    ) as read_at,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', attachment.id,
            'position', attachment.position,
            'kind', attachment.kind,
            'storage_path', attachment.storage_path,
            'mime_type', attachment.mime_type,
            'size_bytes', attachment.size_bytes,
            'width', attachment.width,
            'height', attachment.height,
            'duration_ms', attachment.duration_ms,
            'waveform', attachment.waveform
          )
          order by attachment.position
        )
        from public.message_attachments attachment
        where attachment.message_id = message.id
          and attachment.deleted_at is null
      ),
      '[]'::jsonb
    ) as attachments,
    replied_message.sender_id,
    replied_message.type,
    replied_message.text
  from public.messages message
  join public.conversation_members member
    on member.conversation_id = message.conversation_id
   and member.user_id = auth.uid()
  left join public.messages replied_message
    on replied_message.id = message.reply_to_message_id
   and replied_message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
   and replied_message.deleted_for_everyone_at is null
   and not exists (
     select 1
     from public.message_hidden_for_users hidden_reply
     where hidden_reply.message_id = replied_message.id
       and hidden_reply.user_id = auth.uid()
   )
  where message.conversation_id = target_conversation_id
    and message.deleted_for_everyone_at is null
    and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
    and not exists (
      select 1
      from public.message_hidden_for_users hidden_message
      where hidden_message.message_id = message.id
        and hidden_message.user_id = auth.uid()
    )
    and (
      before_created_at is null
      or (message.created_at, message.id) < (before_created_at, before_message_id)
    )
  order by message.created_at desc, message.id desc
  limit least(greatest(page_size, 1), 100);
$$;

create or replace function public.mark_conversations_read(conversation_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  member record;
  read_timestamp timestamptz := now();
begin
  foreach target_conversation_id in array conversation_ids
  loop
    if public.is_conversation_member(target_conversation_id, current_user_id) then
      insert into public.message_receipts (message_id, user_id, read_at)
      select message.id, current_user_id, read_timestamp
      from public.messages message
      join public.conversation_members conversation_member
        on conversation_member.conversation_id = message.conversation_id
       and conversation_member.user_id = current_user_id
      where message.conversation_id = target_conversation_id
        and message.sender_id <> current_user_id
        and message.deleted_for_everyone_at is null
        and message.created_at > coalesce(
          conversation_member.cleared_at,
          '-infinity'::timestamptz
        )
        and not exists (
          select 1
          from public.message_hidden_for_users hidden_message
          where hidden_message.message_id = message.id
            and hidden_message.user_id = current_user_id
        )
      on conflict (message_id, user_id) do nothing;

      update public.conversation_members
      set last_read_at = read_timestamp
      where conversation_id = target_conversation_id
        and user_id = current_user_id;

      for member in
        select user_id
        from public.conversation_members
        where conversation_id = target_conversation_id
      loop
        perform realtime.send(
          jsonb_build_object(
            'conversation_id', target_conversation_id,
            'reason', 'read'
          ),
          'changed',
          'user:' || member.user_id::text || ':chats',
          true
        );
      end loop;
    end if;
  end loop;
end;
$$;

grant execute on function public.hide_conversations(uuid[], timestamptz) to authenticated;
revoke all on function public.hide_conversations(uuid[], timestamptz) from public, anon;
grant execute on function public.get_conversation_messages(uuid, timestamptz, uuid, integer) to authenticated;
revoke all on function public.get_conversation_messages(uuid, timestamptz, uuid, integer) from public, anon;
grant execute on function public.mark_conversations_read(uuid[]) to authenticated;
revoke all on function public.mark_conversations_read(uuid[]) from public, anon;
