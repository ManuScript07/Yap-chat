create schema if not exists private;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create or replace function private.get_public_profiles_impl()
returns table (
  id uuid,
  username text,
  display_name text,
  birth_date date,
  avatar_url text,
  avatar_storage_path text,
  avatar_updated_at timestamptz,
  gender text,
  bio text,
  onboarding_completed boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.id,
    profile.username,
    profile.display_name,
    profile.birth_date,
    profile.avatar_url,
    profile.avatar_storage_path,
    profile.avatar_updated_at,
    profile.gender,
    profile.bio,
    profile.onboarding_completed,
    profile.created_at,
    profile.updated_at
  from public.profiles profile;
$$;

revoke all on function private.get_public_profiles_impl() from public, anon;
grant execute on function private.get_public_profiles_impl()
to authenticated, service_role;

create or replace view public.public_profiles
with (security_barrier = true, security_invoker = true)
as
select *
from private.get_public_profiles_impl();

revoke all on public.public_profiles from public, anon;
grant select on public.public_profiles to authenticated, service_role;

alter function public.generate_unique_username() set schema private;
alter function private.generate_unique_username()
  rename to generate_unique_username_impl;

alter function public.handle_new_auth_user() set schema private;
alter function private.handle_new_auth_user()
  rename to handle_new_auth_user_impl;

alter function public.broadcast_conversation_change() set schema private;
alter function private.broadcast_conversation_change()
  rename to broadcast_conversation_change_impl;

revoke all on function private.generate_unique_username_impl()
from public, anon;
grant execute on function private.generate_unique_username_impl()
to authenticated, service_role;

revoke all on function private.handle_new_auth_user_impl()
from public, anon, authenticated;
revoke all on function private.broadcast_conversation_change_impl()
from public, anon, authenticated;

alter function public.is_conversation_member(uuid, uuid) set schema private;
alter function private.is_conversation_member(uuid, uuid)
  rename to is_conversation_member_impl;

alter function public.create_direct_conversation(uuid) set schema private;
alter function private.create_direct_conversation(uuid)
  rename to create_direct_conversation_impl;

alter function public.get_chat_summaries() set schema private;
alter function private.get_chat_summaries()
  rename to get_chat_summaries_impl;

alter function public.get_conversation_messages(uuid, timestamptz, uuid, integer)
  set schema private;
alter function private.get_conversation_messages(uuid, timestamptz, uuid, integer)
  rename to get_conversation_messages_impl;

alter function public.send_chat_message(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) set schema private;
alter function private.send_chat_message(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) rename to send_chat_message_impl;

alter function public.mark_conversations_read(uuid[]) set schema private;
alter function private.mark_conversations_read(uuid[])
  rename to mark_conversations_read_impl;

alter function public.hide_conversations(uuid[], timestamptz) set schema private;
alter function private.hide_conversations(uuid[], timestamptz)
  rename to hide_conversations_impl;

alter function public.toggle_conversations_mute(uuid[]) set schema private;
alter function private.toggle_conversations_mute(uuid[])
  rename to toggle_conversations_mute_impl;

alter function public.soft_delete_message(uuid, boolean) set schema private;
alter function private.soft_delete_message(uuid, boolean)
  rename to soft_delete_message_impl;

revoke all on function private.is_conversation_member_impl(uuid, uuid)
from public, anon;
revoke all on function private.create_direct_conversation_impl(uuid)
from public, anon;
revoke all on function private.get_chat_summaries_impl()
from public, anon;
revoke all on function private.get_conversation_messages_impl(
  uuid,
  timestamptz,
  uuid,
  integer
) from public, anon;
revoke all on function private.send_chat_message_impl(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) from public, anon;
revoke all on function private.mark_conversations_read_impl(uuid[])
from public, anon;
revoke all on function private.hide_conversations_impl(uuid[], timestamptz)
from public, anon;
revoke all on function private.toggle_conversations_mute_impl(uuid[])
from public, anon;
revoke all on function private.soft_delete_message_impl(uuid, boolean)
from public, anon;

grant execute on function private.is_conversation_member_impl(uuid, uuid)
to authenticated, service_role;
grant execute on function private.create_direct_conversation_impl(uuid)
to authenticated, service_role;
grant execute on function private.get_chat_summaries_impl()
to authenticated, service_role;
grant execute on function private.get_conversation_messages_impl(
  uuid,
  timestamptz,
  uuid,
  integer
) to authenticated, service_role;
grant execute on function private.send_chat_message_impl(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) to authenticated, service_role;
grant execute on function private.mark_conversations_read_impl(uuid[])
to authenticated, service_role;
grant execute on function private.hide_conversations_impl(uuid[], timestamptz)
to authenticated, service_role;
grant execute on function private.toggle_conversations_mute_impl(uuid[])
to authenticated, service_role;
grant execute on function private.soft_delete_message_impl(uuid, boolean)
to authenticated, service_role;

create function public.is_conversation_member(
  target_conversation_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_conversation_member_impl(
    target_conversation_id,
    target_user_id
  );
$$;

create function public.create_direct_conversation(peer_user_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_direct_conversation_impl(peer_user_id);
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
  is_muted boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_chat_summaries_impl();
$$;

create function public.get_conversation_messages(
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
security invoker
set search_path = ''
as $$
  select *
  from private.get_conversation_messages_impl(
    target_conversation_id,
    before_created_at,
    before_message_id,
    page_size
  );
$$;

create function public.send_chat_message(
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
language sql
security invoker
set search_path = ''
as $$
  select private.send_chat_message_impl(
    message_id,
    target_conversation_id,
    message_type,
    message_text,
    message_latitude,
    message_longitude,
    reply_message_id,
    message_attachments
  );
$$;

create function public.mark_conversations_read(conversation_ids uuid[])
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.mark_conversations_read_impl(conversation_ids);
$$;

create function public.hide_conversations(
  conversation_ids uuid[],
  cleared_before timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.hide_conversations_impl(conversation_ids, cleared_before);
$$;

create function public.toggle_conversations_mute(conversation_ids uuid[])
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.toggle_conversations_mute_impl(conversation_ids);
$$;

create function public.soft_delete_message(
  target_message_id uuid,
  delete_for_everyone boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.soft_delete_message_impl(
    target_message_id,
    delete_for_everyone
  );
$$;

revoke all on function public.is_conversation_member(uuid, uuid)
from public, anon;
revoke all on function public.create_direct_conversation(uuid)
from public, anon;
revoke all on function public.get_chat_summaries()
from public, anon;
revoke all on function public.get_conversation_messages(
  uuid,
  timestamptz,
  uuid,
  integer
) from public, anon;
revoke all on function public.send_chat_message(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) from public, anon;
revoke all on function public.mark_conversations_read(uuid[])
from public, anon;
revoke all on function public.hide_conversations(uuid[], timestamptz)
from public, anon;
revoke all on function public.toggle_conversations_mute(uuid[])
from public, anon;
revoke all on function public.soft_delete_message(uuid, boolean)
from public, anon;

grant execute on function public.is_conversation_member(uuid, uuid)
to authenticated, service_role;
grant execute on function public.create_direct_conversation(uuid)
to authenticated, service_role;
grant execute on function public.get_chat_summaries()
to authenticated, service_role;
grant execute on function public.get_conversation_messages(
  uuid,
  timestamptz,
  uuid,
  integer
) to authenticated, service_role;
grant execute on function public.send_chat_message(
  uuid,
  uuid,
  text,
  text,
  double precision,
  double precision,
  uuid,
  jsonb
) to authenticated, service_role;
grant execute on function public.mark_conversations_read(uuid[])
to authenticated, service_role;
grant execute on function public.hide_conversations(uuid[], timestamptz)
to authenticated, service_role;
grant execute on function public.toggle_conversations_mute(uuid[])
to authenticated, service_role;
grant execute on function public.soft_delete_message(uuid, boolean)
to authenticated, service_role;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute
      'revoke all on function public.rls_auto_enable() '
      'from public, anon, authenticated';
  end if;
end;
$$;

drop policy if exists "Members can read memberships"
on public.conversation_members;
create policy "Members can read memberships"
on public.conversation_members
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Members can read visible messages"
on public.messages;
create policy "Members can read visible messages"
on public.messages
for select to authenticated
using (
  public.is_conversation_member(conversation_id)
  and deleted_for_everyone_at is null
  and created_at > coalesce(
    (
      select member.cleared_at
      from public.conversation_members member
      where member.conversation_id = messages.conversation_id
        and member.user_id = (select auth.uid())
    ),
    '-infinity'::timestamptz
  )
  and not exists (
    select 1
    from public.message_hidden_for_users hidden_message
    where hidden_message.message_id = id
      and hidden_message.user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read visible attachments"
on public.message_attachments;
create policy "Members can read visible attachments"
on public.message_attachments
for select to authenticated
using (
  exists (
    select 1
    from public.messages message
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = (select auth.uid())
    where message.id = message_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = (select auth.uid())
      )
  )
);

drop policy if exists "Members can read receipts"
on public.message_receipts;
create policy "Members can read receipts"
on public.message_receipts
for select to authenticated
using (
  exists (
    select 1
    from public.messages message
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = (select auth.uid())
    where message.id = message_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = (select auth.uid())
      )
  )
);

drop policy if exists "Users can read their hidden messages"
on public.message_hidden_for_users;
create policy "Users can read their hidden messages"
on public.message_hidden_for_users
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Members can receive conversation broadcasts"
on realtime.messages;
create policy "Members can receive conversation broadcasts"
on realtime.messages
for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (
    (select realtime.topic()) =
      'user:' || (select auth.uid())::text || ':chats'
    or exists (
      select 1
      from public.conversation_members member
      where member.user_id = (select auth.uid())
        and (select realtime.topic()) =
          'chat:' || member.conversation_id::text
    )
  )
);
