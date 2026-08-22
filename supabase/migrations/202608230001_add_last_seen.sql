alter table public.profiles
  add column last_seen_at timestamptz,
  add column show_last_seen boolean not null default true;

-- The timestamp is deliberately excluded from public_profiles. Only the
-- chat-summary RPC below can expose it, and only to the user's peer.
drop function public.get_chat_summaries();
drop function private.get_chat_summaries_impl();

create function private.get_chat_summaries_impl()
returns table (
  id uuid,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  peer_avatar_storage_path text,
  last_message_id uuid,
  last_message_text text,
  last_message_type text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  unread_count bigint,
  is_muted boolean,
  peer_last_seen_at timestamptz,
  peer_shows_last_seen boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    conversation.id,
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    latest_message.id,
    latest_message.text,
    latest_message.type,
    latest_message.sender_id,
    coalesce(latest_message.created_at, conversation.created_at),
    (
      select count(*)
      from public.messages unread_message
      where unread_message.conversation_id = conversation.id
        and unread_message.sender_id <> auth.uid()
        and unread_message.deleted_for_everyone_at is null
        and unread_message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
        and not exists (
          select 1
          from public.message_hidden_for_users hidden_message
          where hidden_message.message_id = unread_message.id
            and hidden_message.user_id = auth.uid()
        )
        and not exists (
          select 1
          from public.message_receipts receipt
          where receipt.message_id = unread_message.id
            and receipt.user_id = auth.uid()
        )
    ) as unread_count,
    member.is_muted,
    case when peer.show_last_seen then peer.last_seen_at else null end,
    peer.show_last_seen
  from public.conversation_members member
  join public.conversations conversation
    on conversation.id = member.conversation_id
  join public.profiles peer
    on peer.id = case
      when conversation.user_one_id = auth.uid() then conversation.user_two_id
      else conversation.user_one_id
    end
  left join lateral (
    select message.*
    from public.messages message
    where message.conversation_id = conversation.id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = auth.uid()
      )
    order by message.created_at desc, message.id desc
    limit 1
  ) latest_message on true
  where member.user_id = auth.uid()
    and member.hidden_at is null
  order by coalesce(latest_message.created_at, conversation.created_at) desc;
$$;

create function public.get_chat_summaries()
returns table (
  id uuid,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  peer_avatar_storage_path text,
  last_message_id uuid,
  last_message_text text,
  last_message_type text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  unread_count bigint,
  is_muted boolean,
  peer_last_seen_at timestamptz,
  peer_shows_last_seen boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_chat_summaries_impl();
$$;

revoke all on function public.get_chat_summaries() from public, anon;
grant execute on function public.get_chat_summaries() to authenticated, service_role;

create function private.touch_last_seen_impl()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
  set last_seen_at = now()
  where id = auth.uid();
$$;

revoke all on function private.touch_last_seen_impl() from public, anon;
grant execute on function private.touch_last_seen_impl()
to authenticated, service_role;

create function public.touch_last_seen()
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.touch_last_seen_impl();
$$;

revoke all on function public.touch_last_seen() from public, anon;
grant execute on function public.touch_last_seen() to authenticated, service_role;
