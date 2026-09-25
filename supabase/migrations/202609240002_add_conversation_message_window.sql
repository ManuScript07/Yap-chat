-- A bounded, gap-aware view around a quoted message.  It is deliberately
-- separate from get_conversation_messages: the mobile cache of recent messages
-- must never mistake a distant page for a contiguous continuation.
create function private.get_conversation_message_window_impl(
  target_conversation_id uuid,
  target_message_id uuid default null,
  after_created_at timestamptz default null,
  after_message_id uuid default null,
  page_size integer default 60
)
returns table (
  id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision,
  reply_to_message_id uuid, created_at timestamptz, read_at timestamptz,
  attachments jsonb, reply_sender_id uuid, reply_type text, reply_text text
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  bounded_size integer := least(greatest(coalesce(page_size, 60), 1), 60);
begin
  if target_conversation_id is null
      or (target_message_id is null and
          (after_created_at is null or after_message_id is null))
      or (target_message_id is not null and
          (after_created_at is not null or after_message_id is not null)) then
    raise exception 'Invalid conversation window cursor' using errcode = '22023';
  end if;

  return query
  with member as (
    select cm.cleared_at
    from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = auth.uid()
  ), anchor as (
    select message.created_at, message.id
    from public.messages message
    cross join member
    where target_message_id is not null
      and message.id = target_message_id
      and message.conversation_id = target_conversation_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = auth.uid()
      )
  ), older as (
    select message.id
    from public.messages message
    cross join member
    cross join anchor
    where message.conversation_id = target_conversation_id
      and (message.created_at, message.id) <= (anchor.created_at, anchor.id)
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = auth.uid()
      )
    order by message.created_at desc, message.id desc
    limit (bounded_size + 1) / 2
  ), newer as (
    select message.id
    from public.messages message
    cross join member
    where message.conversation_id = target_conversation_id
      and (
        (target_message_id is not null and exists (
          select 1 from anchor
          where (message.created_at, message.id) > (anchor.created_at, anchor.id)
        ))
        or (target_message_id is null and
            (message.created_at, message.id) > (after_created_at, after_message_id))
      )
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = auth.uid()
      )
    order by message.created_at asc, message.id asc
    limit case when target_message_id is null then bounded_size else bounded_size / 2 end
  ), selected as (
    select older.id from older
    union all
    select newer.id from newer
  )
  select
    message.id, message.conversation_id, message.sender_id, message.type,
    message.text, message.latitude, message.longitude,
    message.reply_to_message_id, message.created_at,
    (select min(receipt.read_at) from public.message_receipts receipt
      where receipt.message_id = message.id
        and receipt.user_id <> message.sender_id) as read_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
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
      ) order by attachment.position)
      from public.message_attachments attachment
      where attachment.message_id = message.id
        and attachment.deleted_at is null
    ), '[]'::jsonb) as attachments,
    replied_message.sender_id as reply_sender_id,
    replied_message.type as reply_type,
    replied_message.text as reply_text
  from selected
  join public.messages message on message.id = selected.id
  cross join member
  left join public.messages replied_message
    on replied_message.id = message.reply_to_message_id
    and replied_message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
    and replied_message.deleted_for_everyone_at is null
    and not exists (
      select 1 from public.message_hidden_for_users hidden_reply
      where hidden_reply.message_id = replied_message.id
        and hidden_reply.user_id = auth.uid()
    )
  order by message.created_at desc, message.id desc;
end;
$$;

create function public.get_conversation_message_window(
  target_conversation_id uuid,
  target_message_id uuid default null,
  after_created_at timestamptz default null,
  after_message_id uuid default null,
  page_size integer default 60
)
returns table (
  id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision,
  reply_to_message_id uuid, created_at timestamptz, read_at timestamptz,
  attachments jsonb, reply_sender_id uuid, reply_type text, reply_text text
)
language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('conversation_messages', 60);
  return query
  select * from private.get_conversation_message_window_impl(
    target_conversation_id, target_message_id, after_created_at,
    after_message_id, page_size
  );
end;
$$;

revoke all on function private.get_conversation_message_window_impl(uuid, uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function private.get_conversation_message_window_impl(uuid, uuid, timestamptz, uuid, integer)
  to authenticated, service_role;
revoke all on function public.get_conversation_message_window(uuid, uuid, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.get_conversation_message_window(uuid, uuid, timestamptz, uuid, integer)
  to authenticated;
