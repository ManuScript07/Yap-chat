create table public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android'
    check (platform in ('android')),
  locale text not null default 'ru'
    check (locale in ('ru', 'en')),
  app_version text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  check (length(token) between 20 and 4096)
);

create index push_devices_user_enabled_idx
  on public.push_devices (user_id)
  where enabled;

alter table public.push_devices enable row level security;

revoke all on table public.push_devices from public, anon, authenticated;
grant select, insert, update, delete on table public.push_devices to service_role;

create table public.push_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  sender_name text not null,
  message_type text not null
    check (message_type in ('text', 'image', 'audio', 'location')),
  message_text text not null default '',
  message_created_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (message_id, recipient_user_id)
);

create index push_notification_outbox_pending_idx
  on public.push_notification_outbox (created_at)
  where status = 'pending';

alter table public.push_notification_outbox enable row level security;

revoke all on table public.push_notification_outbox
  from public, anon, authenticated;
grant select, insert, update, delete
  on table public.push_notification_outbox to service_role;

create or replace function public.register_push_device(
  device_token text,
  device_locale text default 'ru',
  device_app_version text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_token text := trim(device_token);
  normalized_locale text := case
    when lower(trim(coalesce(device_locale, ''))) = 'en' then 'en'
    else 'ru'
  end;
begin
  if current_user_id is null then
    raise exception 'authentication_required';
  end if;

  if length(normalized_token) not between 20 and 4096 then
    raise exception 'invalid_push_token';
  end if;

  insert into public.push_devices (
    user_id,
    token,
    platform,
    locale,
    app_version,
    enabled,
    updated_at,
    last_seen_at
  )
  values (
    current_user_id,
    normalized_token,
    'android',
    normalized_locale,
    nullif(trim(coalesce(device_app_version, '')), ''),
    true,
    now(),
    now()
  )
  on conflict (token) do update
  set
    user_id = excluded.user_id,
    platform = excluded.platform,
    locale = excluded.locale,
    app_version = excluded.app_version,
    enabled = true,
    updated_at = now(),
    last_seen_at = now();

  delete from public.push_devices device
  where device.id in (
    select stale_device.id
    from public.push_devices stale_device
    where stale_device.user_id = current_user_id
    order by stale_device.last_seen_at desc, stale_device.id desc
    offset 10
  );
end;
$$;

create or replace function public.unregister_push_device(device_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication_required';
  end if;

  delete from public.push_devices device
  where device.user_id = current_user_id
    and device.token = trim(device_token);
end;
$$;

revoke all on function public.register_push_device(text, text, text)
  from public, anon;
revoke all on function public.unregister_push_device(text)
  from public, anon;
grant execute on function public.register_push_device(text, text, text)
  to authenticated;
grant execute on function public.unregister_push_device(text)
  to authenticated;

create schema if not exists private;

create or replace function private.enqueue_message_push_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_notification_outbox (
    message_id,
    conversation_id,
    recipient_user_id,
    sender_id,
    sender_name,
    message_type,
    message_text,
    message_created_at
  )
  select
    new.id,
    new.conversation_id,
    recipient.user_id,
    new.sender_id,
    sender.display_name,
    new.type,
    new.text,
    new.created_at
  from public.conversation_members recipient
  join public.profiles sender on sender.id = new.sender_id
  where recipient.conversation_id = new.conversation_id
    and recipient.user_id <> new.sender_id
    and not recipient.is_muted
  on conflict (message_id, recipient_user_id) do nothing;

  return new;
end;
$$;

revoke all on function private.enqueue_message_push_notification()
  from public, anon, authenticated;

create trigger messages_enqueue_push_notification
after insert on public.messages
for each row execute function private.enqueue_message_push_notification();

comment on table public.push_devices is
  'Private FCM device registry. Clients can mutate it only through authenticated RPC functions.';
comment on table public.push_notification_outbox is
  'Server-owned transactional outbox consumed by the push-message Edge Function.';
