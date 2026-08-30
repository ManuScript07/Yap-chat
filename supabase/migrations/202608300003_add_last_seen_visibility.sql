-- One account-level policy controls precise last-seen timestamps everywhere
-- they are exposed. Online presence deliberately remains independent.
alter table private.search_privacy_settings
  add column if not exists last_seen_visibility text not null default 'all'
    check (last_seen_visibility in ('all', 'friends', 'nobody'));

-- The privacy RPCs return the complete cached settings snapshot. Dropping is
-- necessary because PostgreSQL cannot change a function's table return type
-- with CREATE OR REPLACE.
drop function public.get_my_search_privacy_settings();
drop function private.get_my_search_privacy_settings_impl();
drop function public.update_my_search_privacy_settings(boolean, boolean, boolean);
drop function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean);
drop function public.set_my_search_privacy_setting(text, boolean);
drop function private.set_my_search_privacy_setting_impl(text, boolean);

create function private.get_my_search_privacy_settings_impl()
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean,
  last_seen_visibility text
)
language sql stable security definer set search_path = ''
as $$
  select coalesce(settings.search_by_username, true),
         coalesce(settings.search_by_phone, true),
         coalesce(settings.search_by_name, true),
         coalesce(settings.last_seen_visibility, 'all')
  from (select auth.uid() as user_id) viewer
  left join private.search_privacy_settings settings on settings.user_id = viewer.user_id
  where viewer.user_id is not null;
$$;

create function private.broadcast_last_seen_visibility_changed()
returns void language plpgsql security definer set search_path = ''
as $$
declare target record;
begin
  for target in
    select conversation.id as conversation_id, peer.user_id as recipient_id
    from public.conversation_members owner
    join public.conversation_members peer
      on peer.conversation_id = owner.conversation_id
     and peer.user_id <> owner.user_id
    join public.conversations conversation on conversation.id = owner.conversation_id
    where owner.user_id = auth.uid()
  loop
    perform realtime.send(
      jsonb_build_object(
        'conversation_id', target.conversation_id,
        'reason', 'last_seen_visibility'
      ),
      'changed',
      'user:' || target.recipient_id::text || ':chats',
      true
    );
  end loop;
end;
$$;

create function private.set_my_search_privacy_setting_impl(
  setting_key text, is_enabled boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if setting_key not in ('username', 'phone', 'name') or is_enabled is null then
    raise exception using errcode = '22023', message = 'invalid_search_privacy_setting';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name, last_seen_visibility, updated_at
  ) values (
    auth.uid(),
    case when setting_key = 'username' then is_enabled else true end,
    case when setting_key = 'phone' then is_enabled else true end,
    case when setting_key = 'name' then is_enabled else true end,
    'all', now()
  ) on conflict (user_id) do update set
    search_by_username = case when setting_key = 'username' then is_enabled else settings.search_by_username end,
    search_by_phone = case when setting_key = 'phone' then is_enabled else settings.search_by_phone end,
    search_by_name = case when setting_key = 'name' then is_enabled else settings.search_by_name end,
    updated_at = now()
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility;
end;
$$;

create function private.update_my_search_privacy_settings_impl(
  is_searchable_by_username boolean, is_searchable_by_phone boolean, is_searchable_by_name boolean
)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name, last_seen_visibility, updated_at
  ) values (auth.uid(), is_searchable_by_username, is_searchable_by_phone, is_searchable_by_name, 'all', now())
  on conflict (user_id) do update set
    search_by_username = excluded.search_by_username,
    search_by_phone = excluded.search_by_phone,
    search_by_name = excluded.search_by_name,
    updated_at = excluded.updated_at
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility;
end;
$$;

create function private.set_my_last_seen_visibility_impl(visibility text)
returns table (
  search_by_username boolean, search_by_phone boolean, search_by_name boolean,
  last_seen_visibility text
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if visibility not in ('all', 'friends', 'nobody') then
    raise exception using errcode = '22023', message = 'invalid_last_seen_visibility';
  end if;
  perform private.consume_search_privacy_settings_write_quota();
  return query
  insert into private.search_privacy_settings as settings (
    user_id, search_by_username, search_by_phone, search_by_name, last_seen_visibility, updated_at
  ) values (auth.uid(), true, true, true, visibility, now())
  on conflict (user_id) do update set
    last_seen_visibility = excluded.last_seen_visibility,
    updated_at = excluded.updated_at
  returning settings.search_by_username, settings.search_by_phone,
    settings.search_by_name, settings.last_seen_visibility;
  perform private.broadcast_last_seen_visibility_changed();
end;
$$;

create function public.get_my_search_privacy_settings()
returns table (search_by_username boolean, search_by_phone boolean, search_by_name boolean, last_seen_visibility text)
language sql security invoker set search_path = ''
as $$ select * from private.get_my_search_privacy_settings_impl(); $$;

create function public.set_my_search_privacy_setting(setting_key text, is_enabled boolean)
returns table (search_by_username boolean, search_by_phone boolean, search_by_name boolean, last_seen_visibility text)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_search_privacy_setting_impl(setting_key, is_enabled); $$;

create function public.update_my_search_privacy_settings(
  is_searchable_by_username boolean, is_searchable_by_phone boolean, is_searchable_by_name boolean
)
returns table (search_by_username boolean, search_by_phone boolean, search_by_name boolean, last_seen_visibility text)
language sql security invoker set search_path = ''
as $$ select * from private.update_my_search_privacy_settings_impl(is_searchable_by_username, is_searchable_by_phone, is_searchable_by_name); $$;

create function public.set_my_last_seen_visibility(visibility text)
returns table (search_by_username boolean, search_by_phone boolean, search_by_name boolean, last_seen_visibility text)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_last_seen_visibility_impl(visibility); $$;

revoke all on function private.get_my_search_privacy_settings_impl() from public, anon;
revoke all on function private.set_my_search_privacy_setting_impl(text, boolean) from public, anon;
revoke all on function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean) from public, anon;
revoke all on function private.set_my_last_seen_visibility_impl(text) from public, anon;
revoke all on function private.broadcast_last_seen_visibility_changed() from public, anon;
grant execute on function private.get_my_search_privacy_settings_impl() to authenticated, service_role;
grant execute on function private.set_my_search_privacy_setting_impl(text, boolean) to authenticated, service_role;
grant execute on function private.update_my_search_privacy_settings_impl(boolean, boolean, boolean) to authenticated, service_role;
grant execute on function private.set_my_last_seen_visibility_impl(text) to authenticated, service_role;
grant execute on function public.get_my_search_privacy_settings() to authenticated, service_role;
grant execute on function public.set_my_search_privacy_setting(text, boolean) to authenticated, service_role;
grant execute on function public.update_my_search_privacy_settings(boolean, boolean, boolean) to authenticated, service_role;
grant execute on function public.set_my_last_seen_visibility(text) to authenticated, service_role;

-- The value returned to the chat client is already viewer-specific. Existing
-- clients therefore honour the new friends-only policy as well.
create or replace function private.get_chat_summaries_impl()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean
)
language sql stable security definer set search_path = ''
as $$
  select conversation.id, peer.id, peer.username, peer.display_name,
    peer.avatar_url, peer.avatar_storage_path, latest_message.id,
    latest_message.text, latest_message.type, latest_message.sender_id,
    coalesce(latest_message.created_at, conversation.created_at),
    (select count(*) from public.messages unread_message
      where unread_message.conversation_id = conversation.id
        and unread_message.sender_id <> auth.uid()
        and unread_message.deleted_for_everyone_at is null
        and unread_message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
        and not exists (select 1 from public.message_hidden_for_users hidden_message where hidden_message.message_id = unread_message.id and hidden_message.user_id = auth.uid())
        and not exists (select 1 from public.message_receipts receipt where receipt.message_id = unread_message.id and receipt.user_id = auth.uid())),
    member.is_muted,
    case when coalesce(privacy.last_seen_visibility, 'all') = 'all'
           or (coalesce(privacy.last_seen_visibility, 'all') = 'friends' and friendship.id is not null)
         then peer.last_seen_at else null end,
    coalesce(privacy.last_seen_visibility, 'all') = 'all'
      or (coalesce(privacy.last_seen_visibility, 'all') = 'friends' and friendship.id is not null)
  from public.conversation_members member
  join public.conversations conversation on conversation.id = member.conversation_id
  join public.profiles peer on peer.id = case when conversation.user_one_id = auth.uid() then conversation.user_two_id else conversation.user_one_id end
  left join private.search_privacy_settings privacy on privacy.user_id = peer.id
  left join public.friendships friendship on friendship.user_one_id = least(peer.id, auth.uid()) and friendship.user_two_id = greatest(peer.id, auth.uid())
  left join lateral (
    select message.* from public.messages message
    where message.conversation_id = conversation.id and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (select 1 from public.message_hidden_for_users hidden_message where hidden_message.message_id = message.id and hidden_message.user_id = auth.uid())
    order by message.created_at desc, message.id desc limit 1
  ) latest_message on true
  where member.user_id = auth.uid() and member.hidden_at is null
  order by coalesce(latest_message.created_at, conversation.created_at) desc;
$$;

-- Friendship changes affect the friends-only policy too, so refresh the one
-- possible direct chat for both participants.
create or replace function private.broadcast_friend_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare first_user_id uuid; second_user_id uuid; conversation_id uuid;
begin
  if tg_table_name = 'friendships' and tg_op = 'DELETE' then first_user_id := old.user_one_id; second_user_id := old.user_two_id;
  elsif tg_table_name = 'friendships' then first_user_id := new.user_one_id; second_user_id := new.user_two_id;
  elsif tg_op = 'DELETE' then first_user_id := old.sender_id; second_user_id := old.recipient_id;
  else first_user_id := new.sender_id; second_user_id := new.recipient_id; end if;
  perform realtime.send(jsonb_build_object('table', tg_table_name, 'operation', tg_op), 'changed', 'user:' || first_user_id::text || ':friends', true);
  perform realtime.send(jsonb_build_object('table', tg_table_name, 'operation', tg_op), 'changed', 'user:' || second_user_id::text || ':friends', true);
  if tg_table_name = 'friendships' then
    select id into conversation_id from public.conversations
    where user_one_id = first_user_id and user_two_id = second_user_id;
    if conversation_id is not null then
      perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'), 'changed', 'user:' || first_user_id::text || ':chats', true);
      perform realtime.send(jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'), 'changed', 'user:' || second_user_id::text || ':chats', true);
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

alter table public.profiles drop column show_last_seen;
