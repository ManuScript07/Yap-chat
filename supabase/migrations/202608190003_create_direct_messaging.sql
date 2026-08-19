create view public.public_profiles
with (security_barrier = true)
as
select
  id,
  username,
  display_name,
  birth_date,
  avatar_url,
  avatar_storage_path,
  avatar_updated_at,
  gender,
  bio,
  onboarding_completed,
  created_at,
  updated_at
from public.profiles;

revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references public.profiles(id),
  user_two_id uuid not null references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  last_message_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_distinct_users check (user_one_id <> user_two_id),
  constraint conversations_sorted_users check (user_one_id < user_two_id),
  constraint conversations_creator_is_member check (
    created_by = user_one_id or created_by = user_two_id
  ),
  constraint conversations_unique_pair unique (user_one_id, user_two_id)
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_muted boolean not null default false,
  hidden_at timestamptz,
  cleared_at timestamptz,
  last_read_at timestamptz,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  type text not null,
  text text not null default '',
  latitude double precision,
  longitude double precision,
  reply_to_message_id uuid references public.messages(id),
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  cleanup_after timestamptz,
  constraint messages_type check (type in ('text', 'image', 'audio', 'location')),
  constraint messages_text_length check (char_length(text) <= 4096),
  constraint messages_location_payload check (
    (type = 'location' and latitude between -90 and 90 and longitude between -180 and 180)
    or (type <> 'location' and latitude is null and longitude is null)
  )
);

alter table public.conversations
  add constraint conversations_last_message_fk
  foreign key (last_message_id) references public.messages(id) on delete set null;

create table public.message_attachments (
  id uuid primary key,
  message_id uuid not null references public.messages(id) on delete cascade,
  position integer not null,
  kind text not null,
  storage_path text not null,
  mime_type text not null,
  size_bytes bigint not null,
  width integer,
  height integer,
  duration_ms integer,
  waveform jsonb not null default '[]'::jsonb,
  deleted_at timestamptz,
  cleanup_after timestamptz,
  constraint message_attachments_kind check (kind in ('image', 'audio')),
  constraint message_attachments_position check (position >= 0),
  constraint message_attachments_size check (
    (kind = 'image' and size_bytes between 1 and 2097152)
    or (kind = 'audio' and size_bytes between 1 and 5242880)
  ),
  constraint message_attachments_unique_position unique (message_id, position)
);

create table public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table public.message_hidden_for_users (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  cleanup_after timestamptz not null default (now() + interval '3 months'),
  primary key (message_id, user_id)
);

create index conversations_updated_at_idx
on public.conversations (updated_at desc);

create index conversation_members_user_visible_idx
on public.conversation_members (user_id, hidden_at, conversation_id);

create index messages_conversation_created_idx
on public.messages (conversation_id, created_at desc, id desc);

create index messages_sender_idx
on public.messages (sender_id, created_at desc);

create index message_receipts_user_idx
on public.message_receipts (user_id, message_id);

create index message_hidden_user_idx
on public.message_hidden_for_users (user_id, message_id);

create or replace function public.is_conversation_member(
  target_conversation_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id = auth.uid() and exists (
    select 1
    from public.conversation_members member
    where member.conversation_id = target_conversation_id
      and member.user_id = target_user_id
  );
$$;

create or replace function public.create_direct_conversation(peer_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  first_user_id uuid;
  second_user_id uuid;
  conversation_id uuid;
begin
  if current_user_id is null or peer_user_id is null or current_user_id = peer_user_id then
    raise exception 'invalid_conversation_members';
  end if;

  if not exists (
    select 1 from public.profiles where id = peer_user_id
  ) then
    raise exception 'profile_not_found';
  end if;

  first_user_id := least(current_user_id, peer_user_id);
  second_user_id := greatest(current_user_id, peer_user_id);

  insert into public.conversations (
    user_one_id,
    user_two_id,
    created_by
  )
  values (
    first_user_id,
    second_user_id,
    current_user_id
  )
  on conflict (user_one_id, user_two_id) do update
  set updated_at = public.conversations.updated_at
  returning id into conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (conversation_id, first_user_id),
    (conversation_id, second_user_id)
  on conflict do nothing;

  return conversation_id;
end;
$$;

create or replace function public.get_chat_summaries()
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
    member.is_muted
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

create or replace function public.send_chat_message(
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  attachment jsonb;
begin
  if current_user_id is null or not public.is_conversation_member(
    target_conversation_id,
    current_user_id
  ) then
    raise exception 'conversation_access_denied';
  end if;

  if message_type not in ('text', 'image', 'audio', 'location') then
    raise exception 'invalid_message_type';
  end if;

  if exists (
    select 1
    from public.messages existing_message
    where existing_message.id = message_id
      and existing_message.conversation_id = target_conversation_id
      and existing_message.sender_id = current_user_id
  ) then
    return message_id;
  end if;

  if message_type = 'text' and length(trim(coalesce(message_text, ''))) = 0 then
    raise exception 'empty_message';
  end if;

  if reply_message_id is not null and not exists (
    select 1
    from public.messages replied_message
    where replied_message.id = reply_message_id
      and replied_message.conversation_id = target_conversation_id
      and replied_message.deleted_for_everyone_at is null
  ) then
    raise exception 'invalid_reply_message';
  end if;

  if message_type = 'image' and (
    jsonb_array_length(message_attachments) < 1
    or jsonb_array_length(message_attachments) > 5
  ) then
    raise exception 'invalid_image_count';
  end if;

  if message_type = 'audio' and jsonb_array_length(message_attachments) <> 1 then
    raise exception 'invalid_audio_count';
  end if;

  if message_type in ('text', 'location') and jsonb_array_length(message_attachments) <> 0 then
    raise exception 'unexpected_attachments';
  end if;

  insert into public.messages (
    id,
    conversation_id,
    sender_id,
    type,
    text,
    latitude,
    longitude,
    reply_to_message_id
  )
  values (
    message_id,
    target_conversation_id,
    current_user_id,
    message_type,
    coalesce(message_text, ''),
    message_latitude,
    message_longitude,
    reply_message_id
  );

  for attachment in select value from jsonb_array_elements(message_attachments)
  loop
    if attachment ->> 'storage_path' not like (
      target_conversation_id::text || '/' || current_user_id::text || '/' || message_id::text || '/%'
    ) then
      raise exception 'invalid_attachment_path';
    end if;

    insert into public.message_attachments (
      id,
      message_id,
      position,
      kind,
      storage_path,
      mime_type,
      size_bytes,
      width,
      height,
      duration_ms,
      waveform
    )
    values (
      (attachment ->> 'id')::uuid,
      message_id,
      (attachment ->> 'position')::integer,
      attachment ->> 'kind',
      attachment ->> 'storage_path',
      attachment ->> 'mime_type',
      (attachment ->> 'size_bytes')::bigint,
      (attachment ->> 'width')::integer,
      (attachment ->> 'height')::integer,
      (attachment ->> 'duration_ms')::integer,
      coalesce(attachment -> 'waveform', '[]'::jsonb)
    );
  end loop;

  return message_id;
end;
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
  read_timestamp timestamptz := now();
begin
  foreach target_conversation_id in array conversation_ids
  loop
    if public.is_conversation_member(target_conversation_id, current_user_id) then
      insert into public.message_receipts (message_id, user_id, read_at)
      select message.id, current_user_id, read_timestamp
      from public.messages message
      join public.conversation_members member
        on member.conversation_id = message.conversation_id
       and member.user_id = current_user_id
      where message.conversation_id = target_conversation_id
        and message.sender_id <> current_user_id
        and message.deleted_for_everyone_at is null
        and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
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

      perform realtime.send(
        jsonb_build_object('conversation_id', target_conversation_id, 'reason', 'read'),
        'changed',
        'chat:' || target_conversation_id::text,
        true
      );

      perform realtime.send(
        jsonb_build_object('conversation_id', target_conversation_id, 'reason', 'read'),
        'changed',
        'user:' || current_user_id::text || ':chats',
        true
      );
    end if;
  end loop;
end;
$$;

create or replace function public.hide_conversations(conversation_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members
  set
    hidden_at = now(),
    cleared_at = now()
  where user_id = auth.uid()
    and conversation_id = any(conversation_ids);

  perform realtime.send(
    jsonb_build_object('conversation_ids', conversation_ids, 'reason', 'hidden'),
    'changed',
    'user:' || auth.uid()::text || ':chats',
    true
  );
end;
$$;

create or replace function public.toggle_conversations_mute(conversation_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members
  set is_muted = not is_muted
  where user_id = auth.uid()
    and conversation_id = any(conversation_ids);

  perform realtime.send(
    jsonb_build_object('conversation_ids', conversation_ids, 'reason', 'muted'),
    'changed',
    'user:' || auth.uid()::text || ':chats',
    true
  );
end;
$$;

create or replace function public.soft_delete_message(
  target_message_id uuid,
  delete_for_everyone boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  target_message public.messages%rowtype;
  deletion_timestamp timestamptz := now();
begin
  select * into target_message
  from public.messages
  where id = target_message_id;

  if target_message.id is null or not public.is_conversation_member(
    target_message.conversation_id,
    current_user_id
  ) then
    raise exception 'message_access_denied';
  end if;

  if delete_for_everyone and target_message.sender_id = current_user_id then
    update public.messages
    set
      deleted_for_everyone_at = deletion_timestamp,
      cleanup_after = deletion_timestamp + interval '3 months'
    where id = target_message_id;

    update public.message_attachments
    set
      deleted_at = deletion_timestamp,
      cleanup_after = deletion_timestamp + interval '3 months'
    where message_id = target_message_id;
  else
    insert into public.message_hidden_for_users (message_id, user_id)
    values (target_message_id, current_user_id)
    on conflict (message_id, user_id) do nothing;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted'
    ),
    'changed',
    'chat:' || target_message.conversation_id::text,
    true
  );

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted'
    ),
    'changed',
    'user:' || current_user_id::text || ':chats',
    true
  );
end;
$$;

create or replace function public.broadcast_conversation_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_conversation_id uuid := new.conversation_id;
  member record;
begin
  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    update public.conversation_members
    set hidden_at = null
    where conversation_id = target_conversation_id;

    update public.conversations
    set
      last_message_id = new.id,
      updated_at = new.created_at
    where id = target_conversation_id;
  end if;

  perform realtime.send(
    jsonb_build_object('conversation_id', target_conversation_id, 'reason', lower(tg_op)),
    'changed',
    'chat:' || target_conversation_id::text,
    true
  );

  for member in
    select user_id
    from public.conversation_members
    where conversation_id = target_conversation_id
  loop
    perform realtime.send(
      jsonb_build_object('conversation_id', target_conversation_id, 'reason', lower(tg_op)),
      'changed',
      'user:' || member.user_id::text || ':chats',
      true
    );
  end loop;

  return new;
end;
$$;

create trigger messages_broadcast_change
after insert or update on public.messages
for each row execute function public.broadcast_conversation_change();

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.message_receipts enable row level security;
alter table public.message_hidden_for_users enable row level security;

create policy "Members can read conversations"
on public.conversations
for select to authenticated
using (public.is_conversation_member(id));

create policy "Members can read memberships"
on public.conversation_members
for select to authenticated
using (user_id = auth.uid());

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
        and member.user_id = auth.uid()
    ),
    '-infinity'::timestamptz
  )
  and not exists (
    select 1
    from public.message_hidden_for_users hidden_message
    where hidden_message.message_id = id
      and hidden_message.user_id = auth.uid()
  )
);

create policy "Members can read visible attachments"
on public.message_attachments
for select to authenticated
using (
  exists (
    select 1
    from public.messages message
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = auth.uid()
    where message.id = message_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = auth.uid()
      )
  )
);

create policy "Members can read receipts"
on public.message_receipts
for select to authenticated
using (
  exists (
    select 1
    from public.messages message
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = auth.uid()
    where message.id = message_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = auth.uid()
      )
  )
);

create policy "Users can read their hidden messages"
on public.message_hidden_for_users
for select to authenticated
using (user_id = auth.uid());

grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant select on public.messages to authenticated;
grant select on public.message_attachments to authenticated;
grant select on public.message_receipts to authenticated;
grant select on public.message_hidden_for_users to authenticated;

grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;
grant execute on function public.create_direct_conversation(uuid) to authenticated;
grant execute on function public.get_chat_summaries() to authenticated;
grant execute on function public.get_conversation_messages(uuid, timestamptz, uuid, integer) to authenticated;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb) to authenticated;
grant execute on function public.mark_conversations_read(uuid[]) to authenticated;
grant execute on function public.hide_conversations(uuid[]) to authenticated;
grant execute on function public.toggle_conversations_mute(uuid[]) to authenticated;
grant execute on function public.soft_delete_message(uuid, boolean) to authenticated;

revoke all on function public.is_conversation_member(uuid, uuid) from public, anon;
revoke all on function public.create_direct_conversation(uuid) from public, anon;
revoke all on function public.get_chat_summaries() from public, anon;
revoke all on function public.get_conversation_messages(uuid, timestamptz, uuid, integer) from public, anon;
revoke all on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb) from public, anon;
revoke all on function public.mark_conversations_read(uuid[]) from public, anon;
revoke all on function public.hide_conversations(uuid[]) from public, anon;
revoke all on function public.toggle_conversations_mute(uuid[]) from public, anon;
revoke all on function public.soft_delete_message(uuid, boolean) from public, anon;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'chat-images',
    'chat-images',
    false,
    2097152,
    array['image/jpeg']
  ),
  (
    'chat-audio',
    'chat-audio',
    false,
    5242880,
    array['audio/mp4', 'audio/aac', 'audio/ogg', 'audio/webm']
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Conversation members can read chat media"
on storage.objects
for select to authenticated
using (
  bucket_id in ('chat-images', 'chat-audio')
  and exists (
    select 1
    from public.messages message
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = auth.uid()
    where message.id = ((storage.foldername(name))[3])::uuid
      and message.conversation_id = ((storage.foldername(name))[1])::uuid
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (
        select 1
        from public.message_hidden_for_users hidden_message
        where hidden_message.message_id = message.id
          and hidden_message.user_id = auth.uid()
      )
  )
);

create policy "Conversation members can upload chat media"
on storage.objects
for insert to authenticated
with check (
  bucket_id in ('chat-images', 'chat-audio')
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);

create policy "Members can receive conversation broadcasts"
on realtime.messages
for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (
    (select realtime.topic()) = 'user:' || auth.uid()::text || ':chats'
    or exists (
      select 1
      from public.conversation_members member
      where member.user_id = auth.uid()
        and (select realtime.topic()) = 'chat:' || member.conversation_id::text
    )
  )
);

create policy "Authenticated users can receive presence"
on realtime.messages
for select to authenticated
using (
  realtime.messages.extension = 'presence'
  and (select realtime.topic()) = 'online'
);

create policy "Authenticated users can track presence"
on realtime.messages
for insert to authenticated
with check (
  realtime.messages.extension = 'presence'
  and (select realtime.topic()) = 'online'
);
