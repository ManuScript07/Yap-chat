-- Keep the public RPC, quotas and projection intact. Resolve the one-row
-- visibility/anchor lookups before the bounded scans so both cursor columns
-- become index conditions rather than JOIN/EXISTS filters over chat history.
create or replace function private.get_conversation_message_window_impl(
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
  current_user_id uuid := auth.uid();
  visible_after timestamptz;
  cursor_created_at timestamptz;
  cursor_message_id uuid;
  older_size integer := 0;
  newer_size integer := bounded_size;
begin
  if target_conversation_id is null
      or (target_message_id is null and
          (after_created_at is null or after_message_id is null))
      or (target_message_id is not null and
          (after_created_at is not null or after_message_id is not null)) then
    raise exception 'Invalid conversation window cursor' using errcode = '22023';
  end if;

  select coalesce(cm.cleared_at, '-infinity'::timestamptz)
  into visible_after
  from public.conversation_members cm
  where cm.conversation_id = target_conversation_id
    and cm.user_id = current_user_id;
  if not found then
    return;
  end if;

  if target_message_id is not null then
    select message.created_at, message.id
    into cursor_created_at, cursor_message_id
    from public.messages message
    where message.id = target_message_id
      and message.conversation_id = target_conversation_id
      and message.deleted_for_everyone_at is null
      and message.created_at > visible_after
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = current_user_id
      );
    if not found then
      return;
    end if;
    -- Preserve the existing split, including the anchor on the older side.
    older_size := (bounded_size + 1) / 2;
    newer_size := bounded_size / 2;
  else
    cursor_created_at := after_created_at;
    cursor_message_id := after_message_id;
  end if;

  -- STABLE preserves the caller's statement snapshot across the lookups and
  -- these scans. LIMIT 0 skips the older scan in after-cursor mode entirely.
  return query
  with older as (
    select message.id
    from public.messages message
    where message.conversation_id = target_conversation_id
      and (message.created_at, message.id) <= (cursor_created_at, cursor_message_id)
      and message.created_at > visible_after
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = current_user_id
      )
    order by message.created_at desc, message.id desc
    limit older_size
  ), newer as (
    select message.id
    from public.messages message
    where message.conversation_id = target_conversation_id
      and (message.created_at, message.id) > (cursor_created_at, cursor_message_id)
      and message.created_at > visible_after
      and message.deleted_for_everyone_at is null
      and not exists (
        select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = current_user_id
      )
    order by message.created_at asc, message.id asc
    limit newer_size
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
  left join public.messages replied_message
    on replied_message.id = message.reply_to_message_id
    and replied_message.created_at > visible_after
    and replied_message.deleted_for_everyone_at is null
    and not exists (
      select 1 from public.message_hidden_for_users hidden_reply
      where hidden_reply.message_id = replied_message.id
        and hidden_reply.user_id = current_user_id
    )
  order by message.created_at desc, message.id desc;
end;
$$;

revoke all on function private.get_conversation_message_window_impl(uuid, uuid, timestamptz, uuid, integer)
  from public, anon;
grant execute on function private.get_conversation_message_window_impl(uuid, uuid, timestamptz, uuid, integer)
  to authenticated, service_role;
