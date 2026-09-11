-- Reversible account deletion.  A request immediately makes the account
-- inaccessible and invisible, but keeps its data for thirty days so the owner
-- can restore it.  Finalisation deliberately leaves an anonymous profile
-- tombstone: direct-conversation and message foreign keys remain valid while
-- all account-identifying profile and Auth data is removed.

create extension if not exists pg_cron with schema pg_catalog;

alter table public.profiles
  add column if not exists account_deletion_requested_at timestamptz;

create index if not exists profiles_account_deletion_requested_at_idx
  on public.profiles (account_deletion_requested_at)
  where account_deletion_requested_at is not null;

create table private.account_deletion_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  target_user_id uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default statement_timestamp(),
  scheduled_for timestamptz not null default (
    statement_timestamp() + interval '30 days'
  ),
  restored_at timestamptz,
  finalized_at timestamptz,
  requested_by text not null default 'self',
  note text,
  -- The public self-service path is always thirty days.  Keeping this lower
  -- bound at the request timestamp lets an administrator use a short window
  -- on a local development database without introducing a production bypass.
  check (scheduled_for >= requested_at),
  check (finalized_at is null or finalized_at >= requested_at),
  check (restored_at is null or restored_at >= requested_at)
);

create unique index account_deletion_requests_one_active_target_idx
  on private.account_deletion_requests (target_user_id)
  where restored_at is null;

create index account_deletion_requests_due_idx
  on private.account_deletion_requests (scheduled_for, target_user_id)
  where restored_at is null and finalized_at is null;

revoke all on table private.account_deletion_requests
  from public, anon, authenticated;

comment on table private.account_deletion_requests is
  'Support audit and administrative deletion queue. Inserting an active row immediately disables the target account; set restored_at to restore before scheduled_for.';

create or replace function private.is_account_pending_deletion(
  target_account_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_account_user_id is not null and exists (
    select 1
    from private.account_deletion_requests request
    where request.target_user_id = target_account_user_id
      and request.restored_at is null
  );
$$;

create or replace function private.require_active_account()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if private.is_account_globally_banned(auth.uid()) then
    raise exception using errcode = 'P0001', message = 'account_globally_banned';
  end if;
  if private.is_account_pending_deletion(auth.uid()) then
    raise exception using errcode = 'P0001', message = 'account_pending_deletion';
  end if;
end;
$$;

-- This function is intentionally private and service-role-only.  The mobile
-- client reaches it through the authenticated Edge Function, which derives
-- the target id from the JWT rather than accepting one from the device.
create or replace function private.request_account_deletion_impl(
  target_account_user_id uuid,
  requested_by_value text default 'self',
  requested_note text default null,
  retention interval default interval '30 days'
)
returns table (scheduled_for timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_request private.account_deletion_requests%rowtype;
  normalized_retention interval := coalesce(retention, interval '30 days');
begin
  if target_account_user_id is null then
    raise exception using errcode = '22023', message = 'invalid_deletion_target';
  end if;
  if normalized_retention < interval '1 minute' or normalized_retention > interval '90 days' then
    raise exception using errcode = '22023', message = 'invalid_deletion_retention';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account-deletion:' || target_account_user_id::text, 0)
  );

  if not exists (select 1 from auth.users user_row where user_row.id = target_account_user_id) then
    raise exception using errcode = 'P0002', message = 'account_not_found';
  end if;

  select request.* into existing_request
  from private.account_deletion_requests request
  where request.target_user_id = target_account_user_id
    and request.restored_at is null
  order by request.requested_at desc
  limit 1;

  if existing_request.id is not null then
    return query select existing_request.scheduled_for;
    return;
  end if;

  if coalesce(nullif(btrim(requested_by_value), ''), 'self') = 'self'
     and (
       select count(*)
       from private.account_deletion_requests request
       where request.target_user_id = target_account_user_id
         and request.requested_by = 'self'
         and request.requested_at > statement_timestamp() - interval '1 day'
     ) >= 3 then
    raise exception using errcode = 'P0001', message = 'account_deletion_rate_limited';
  end if;

  insert into private.account_deletion_requests (
    target_user_id, scheduled_for, requested_by, note
  ) values (
    target_account_user_id,
    statement_timestamp() + normalized_retention,
    coalesce(nullif(btrim(requested_by_value), ''), 'admin'),
    nullif(btrim(requested_note), '')
  )
  returning * into existing_request;

  return query select existing_request.scheduled_for;
end;
$$;

-- Direct inserts into private.account_deletion_requests are the moderation
-- interface.  The trigger deliberately owns the state transition as well, so
-- an administrator cannot create a record that looks deleted in support
-- tooling while the account remains usable.
create or replace function private.apply_account_deletion_request_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and old.finalized_at is not null
     and new.restored_at is distinct from old.restored_at then
    raise exception using errcode = 'P0001', message = 'account_deletion_finalized';
  end if;
  if tg_op = 'INSERT' then
    -- Friend requests must not reappear unexpectedly after restoration.  The
    -- friendship graph stays intact and becomes visible again on restore.
    delete from public.friend_requests request
    where new.target_user_id in (request.sender_id, request.recipient_id);
    delete from public.push_devices device where device.user_id = new.target_user_id;
    delete from private.user_presence_sessions session where session.user_id = new.target_user_id;
    delete from private.user_presence_watch_targets watch
    where watch.target_user_id = new.target_user_id or watch.watcher_user_id = new.target_user_id;
    update public.profiles
    set account_deletion_requested_at = new.requested_at
    where id = new.target_user_id;
    perform private.broadcast_user_presence_change(new.target_user_id, false);
  elsif tg_op = 'UPDATE' and old.restored_at is null and new.restored_at is not null then
    update public.profiles
    set account_deletion_requested_at = null
    where id = new.target_user_id;
  end if;
  return new;
end;
$$;

create trigger account_deletion_requests_apply_change
after insert or update of restored_at on private.account_deletion_requests
for each row execute function private.apply_account_deletion_request_change();

create or replace function private.restore_account_deletion_impl(
  target_account_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  active_request private.account_deletion_requests%rowtype;
begin
  if target_account_user_id is null then
    raise exception using errcode = '22023', message = 'invalid_deletion_target';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account-deletion:' || target_account_user_id::text, 0)
  );

  select request.* into active_request
  from private.account_deletion_requests request
  where request.target_user_id = target_account_user_id
    and request.restored_at is null
  order by request.requested_at desc
  limit 1
  for update;

  if active_request.id is null then
    raise exception using errcode = 'P0002', message = 'account_deletion_not_found';
  end if;
  if active_request.finalized_at is not null
     or active_request.scheduled_for <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'account_deletion_expired';
  end if;

  update private.account_deletion_requests
  set restored_at = statement_timestamp()
  where id = active_request.id;

end;
$$;

-- The Edge Functions use these SECURITY INVOKER bridges with their service
-- role.  They are not executable by anon/authenticated clients, so private
-- schema internals never need to be exposed through PostgREST.
create function public.request_account_deletion_from_service(
  target_user_id uuid,
  requested_by_value text default 'self',
  requested_note text default null
)
returns table (scheduled_for timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from private.request_account_deletion_impl(
    target_user_id, requested_by_value, requested_note, interval '30 days'
  );
$$;

create function public.restore_account_deletion_from_service(
  target_user_id uuid
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.restore_account_deletion_impl(target_user_id);
$$;

-- Finalisation removes the data that would otherwise keep a deleted account
-- identifiable.  Direct chats remain structurally valid, but the account,
-- profile and sent messages are no longer available through the application.
create or replace function private.finalize_due_account_deletions(
  maximum_accounts integer default 25
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row record;
  normalized_maximum integer := least(greatest(coalesce(maximum_accounts, 25), 1), 100);
  finalised_count integer := 0;
begin
  for request_row in
    select request.id, request.target_user_id
    from private.account_deletion_requests request
    where request.restored_at is null
      and request.finalized_at is null
      and request.scheduled_for <= statement_timestamp()
    order by request.scheduled_for, request.id
    limit normalized_maximum
    for update skip locked
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('account-deletion:' || request_row.target_user_id::text, 0)
    );

    update public.messages message
    set deleted_for_everyone_at = coalesce(message.deleted_for_everyone_at, statement_timestamp()),
        cleanup_after = coalesce(message.cleanup_after, statement_timestamp() + interval '3 months')
    where message.sender_id = request_row.target_user_id;

    update public.message_attachments attachment
    set deleted_at = coalesce(attachment.deleted_at, statement_timestamp()),
        cleanup_after = coalesce(attachment.cleanup_after, statement_timestamp() + interval '3 months')
    from public.messages message
    where attachment.message_id = message.id
      and message.sender_id = request_row.target_user_id;

    -- Storage owns storage.objects and explicitly rejects direct SQL deletes.
    -- The profile/photo references below are removed and the deletion-aware
    -- Storage policy makes these objects unreadable immediately.  A separate
    -- privileged Storage API cleanup job can reclaim the now-orphaned files
    -- later without bypassing Storage's integrity protections.

    delete from public.profile_photos photo where photo.profile_id = request_row.target_user_id;
    delete from public.user_locations location where location.user_id = request_row.target_user_id;
    delete from public.user_blocks block
    where request_row.target_user_id in (block.blocker_user_id, block.blocked_user_id);
    delete from public.friendships friendship
    where request_row.target_user_id in (friendship.user_one_id, friendship.user_two_id);
    delete from public.friend_requests friend_request
    where request_row.target_user_id in (friend_request.sender_id, friend_request.recipient_id);
    delete from private.user_reports report
    where request_row.target_user_id in (report.reporter_user_id, report.target_user_id);
    delete from private.user_report_daily_limits report_limit
    where report_limit.reporter_user_id = request_row.target_user_id;
    delete from private.user_presence_sessions session where session.user_id = request_row.target_user_id;
    delete from private.user_presence_watch_targets watch
    where watch.target_user_id = request_row.target_user_id or watch.watcher_user_id = request_row.target_user_id;
    delete from public.push_devices device where device.user_id = request_row.target_user_id;
    delete from private.account_settings setting where setting.user_id = request_row.target_user_id;
    delete from private.search_privacy_settings privacy where privacy.user_id = request_row.target_user_id;
    delete from private.precise_location_exclusions exclusion
    where request_row.target_user_id in (exclusion.owner_user_id, exclusion.viewer_user_id);
    delete from private.profile_view_counters counter
    where request_row.target_user_id in (counter.profile_id, counter.viewer_id);
    delete from private.profile_view_daily_counters counter
    where request_row.target_user_id in (counter.profile_id, counter.viewer_id);

    update public.profiles
    set username = 'deleted_' || left(replace(request_row.target_user_id::text, '-', ''), 16),
        display_name = 'Удалённый пользователь',
        birth_date = null,
        avatar_url = null,
        avatar_storage_path = null,
        avatar_updated_at = null,
        gender = 'unspecified',
        bio = '',
        last_seen_at = null,
        phone_lookup_hash = null,
        account_deletion_requested_at = statement_timestamp()
    where id = request_row.target_user_id;

    -- Preserve a non-identifying Auth tombstone so existing direct-message
    -- foreign keys survive.  Removing OAuth identities makes the old Yandex
    -- identity unavailable for sign-in; an active global ban continues to
    -- catch a new registration by its separately retained identity hashes.
    delete from auth.identities identity where identity.user_id = request_row.target_user_id;
    update auth.users
    set email = 'deleted+' || request_row.target_user_id::text || '@invalid.yapchat.local',
        raw_user_meta_data = '{}'::jsonb,
        raw_app_meta_data = '{}'::jsonb,
        phone = null,
        banned_until = 'infinity'::timestamptz
    where id = request_row.target_user_id;

    update private.account_deletion_requests
    set finalized_at = statement_timestamp()
    where id = request_row.id;
    finalised_count := finalised_count + 1;
  end loop;
  return finalised_count;
end;
$$;

-- Deleted accounts are not presence participants or recipients.
create or replace function private.is_user_online(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select $1 is not null
    and not private.is_account_globally_banned($1)
    and not private.is_account_pending_deletion($1)
    and exists (
      select 1
      from private.user_presence_sessions session
      where session.user_id = $1
        and session.expires_at > statement_timestamp()
    );
$$;

create or replace function private.can_receive_user_presence(
  viewer_user_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select $1 is not null
    and $2 is not null
    and $1 <> $2
    and not private.is_account_globally_banned($1)
    and not private.is_account_globally_banned($2)
    and not private.is_account_pending_deletion($1)
    and not private.is_account_pending_deletion($2)
    and not private.is_blocked_by_impl($2, $1);
$$;

-- Account access is the one Data API exception needed to render the local
-- recovery screen.  It returns no profile data other than the existing safe
-- username and support contact.
drop function if exists public.get_my_account_access();
drop function if exists private.get_my_account_access_impl();

create function private.get_my_account_access_impl()
returns table (
  is_banned boolean,
  is_deletion_pending boolean,
  username text,
  support_email text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return query
  select
    private.is_account_globally_banned(account.user_id)
      or flags.finalized,
    private.is_account_pending_deletion(account.user_id)
      and not flags.finalized,
    profile.username,
    content.support_email
  from (select auth.uid() as user_id) account
  cross join lateral (
    select exists (
      select 1 from private.account_deletion_requests request
      where request.target_user_id = account.user_id
        and request.restored_at is null
        and request.finalized_at is not null
    ) as finalized
  ) flags
  left join public.profiles profile on profile.id = account.user_id
  left join private.app_public_content content on content.singleton;
end;
$$;

create function public.get_my_account_access()
returns table (
  is_banned boolean,
  is_deletion_pending boolean,
  username text,
  support_email text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_my_account_access_impl();
$$;

-- Existing profile change subscriptions already own the relevant realtime
-- channels.  Treat a deletion-state change as an identity refresh so chat and
-- friend caches converge without polling or an additional subscription.
drop trigger if exists profiles_broadcast_public_change on public.profiles;
create trigger profiles_broadcast_public_change
after update of
  username, display_name, birth_date, gender, bio, avatar_url,
  avatar_storage_path, avatar_updated_at, updated_at,
  account_deletion_requested_at
on public.profiles
for each row
when (
  old.username is distinct from new.username
  or old.display_name is distinct from new.display_name
  or old.birth_date is distinct from new.birth_date
  or old.gender is distinct from new.gender
  or old.bio is distinct from new.bio
  or old.avatar_url is distinct from new.avatar_url
  or old.avatar_storage_path is distinct from new.avatar_storage_path
  or old.avatar_updated_at is distinct from new.avatar_updated_at
  or old.updated_at is distinct from new.updated_at
  or old.account_deletion_requested_at is distinct from new.account_deletion_requested_at
)
execute function private.broadcast_public_profile_change();

-- A deleted peer is deliberately distinct from a global ban in the payload so
-- the client can offer only “delete chat”, never an unblock control.
drop function if exists public.get_chat_summaries();
drop function if exists private.get_chat_summaries_rate_limited_impl();

create function private.get_chat_summaries_rate_limited_impl()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_deleted boolean, peer_is_online boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select summary.id, summary.peer_id,
    case when flags.redact then '' else summary.peer_username end,
    case
      when flags.globally_banned then 'Заблокированный пользователь'
      when flags.pending_deletion then 'Удалённый пользователь'
      else summary.peer_display_name
    end,
    case when flags.redact then null else summary.peer_avatar_url end,
    case when flags.redact then null else summary.peer_avatar_storage_path end,
    summary.last_message_id, summary.last_message_text, summary.last_message_type,
    summary.last_message_sender_id, summary.last_message_at, summary.unread_count,
    summary.is_muted,
    case when flags.redact then null else summary.peer_last_seen_at end,
    case when flags.redact then false else summary.peer_shows_last_seen end,
    flags.blocked_by_me, flags.blocked_by_peer, flags.globally_banned,
    flags.pending_deletion,
    not flags.redact and private.is_user_online(summary.peer_id)
  from private.get_chat_summaries_impl() summary
  cross join lateral (
    select
      private.is_account_globally_banned(summary.peer_id) as globally_banned,
      private.is_account_pending_deletion(summary.peer_id) as pending_deletion,
      private.is_blocked_by_impl(auth.uid(), summary.peer_id) as blocked_by_me,
      private.is_blocked_by_impl(summary.peer_id, auth.uid()) as blocked_by_peer
  ) flags_raw
  cross join lateral (
    select flags_raw.globally_banned, flags_raw.pending_deletion,
      flags_raw.blocked_by_me, flags_raw.blocked_by_peer,
      (flags_raw.globally_banned or flags_raw.pending_deletion
        or flags_raw.blocked_by_peer) as redact
  ) flags;
$$;

create function public.get_chat_summaries()
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_deleted boolean, peer_is_online boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('chat_summaries', 30);
  return query select * from private.get_chat_summaries_rate_limited_impl();
end;
$$;

create or replace function public.create_direct_conversation(peer_user_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if private.is_account_globally_banned(peer_user_id)
     or private.is_account_pending_deletion(peer_user_id)
     or private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.create_direct_conversation_impl(peer_user_id);
end;
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
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  if exists (
    select 1 from public.messages message
    where message.id = message_id
      and message.conversation_id = target_conversation_id
      and message.sender_id = auth.uid()
  ) then
    return message_id;
  end if;

  perform private.consume_chat_message_write_quota();
  peer_user_id := private.get_direct_conversation_peer_impl(target_conversation_id);
  if peer_user_id is null
     or private.is_account_globally_banned(peer_user_id)
     or private.is_account_pending_deletion(peer_user_id)
     or private.is_conversation_blocked_impl(target_conversation_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.send_chat_message_impl(
    message_id, target_conversation_id, message_type, message_text,
    message_latitude, message_longitude, reply_message_id, message_attachments
  );
end;
$$;

create or replace function public.send_friend_request(peer_user_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if private.is_account_globally_banned(peer_user_id)
     or private.is_account_pending_deletion(peer_user_id)
     or private.is_user_pair_blocked_impl(auth.uid(), peer_user_id) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  return private.send_friend_request_impl(peer_user_id);
end;
$$;

create or replace function public.respond_friend_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  peer_user_id := private.get_pending_friend_request_peer_impl(target_request_id);
  if peer_user_id is null then
    raise exception using errcode = 'P0001', message = 'friend_request_not_found';
  end if;
  if accept_request and (
    private.is_account_globally_banned(peer_user_id)
    or private.is_account_pending_deletion(peer_user_id)
  ) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  perform private.respond_friend_request_impl(target_request_id, accept_request);
end;
$$;

-- Discovery and shared links never disclose an account awaiting deletion.
create or replace function public.search_friend_candidates(
  search_query text,
  result_limit integer default 10
)
returns table (
  id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select candidate.*
  from private.search_friend_candidates_impl(search_query, result_limit) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_account_pending_deletion(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.match_contact_phones(phone_numbers text[])
returns table (
  phone_number text, id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select candidate.*
  from private.match_contact_phones_impl(phone_numbers) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_account_pending_deletion(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function public.match_new_friend_contact_phones(
  phone_numbers text[], friend_user_ids uuid[]
)
returns table (
  phone_number text, id uuid, request_id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text, friend_count bigint, relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select candidate.*
  from private.match_new_friend_contact_phones_impl(phone_numbers, friend_user_ids) candidate
  where not private.is_account_globally_banned(candidate.id)
    and not private.is_account_pending_deletion(candidate.id)
    and not private.is_blocked_by_impl(candidate.id, auth.uid());
$$;

create or replace function private.resolve_shared_profile_username_impl(
  shared_username text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text := lower(btrim(coalesce(shared_username, '')));
  resolved_user_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  perform private.require_active_account();
  if normalized_username !~ '^[a-z0-9_]{3,24}$' then return null; end if;
  perform private.consume_shared_profile_link_quota();
  select profile.id into resolved_user_id
  from public.profiles profile
  where profile.username = normalized_username
    and profile.onboarding_completed
    and not private.is_account_globally_banned(profile.id)
    and not private.is_account_pending_deletion(profile.id)
  limit 1;
  return resolved_user_id;
end;
$$;

-- A deletion-pending account is absent from every friends surface.  These
-- filters live in the paginated implementations (rather than only their
-- public wrappers) so cursors, total counts and has_more remain correct.
create or replace function private.get_friends_page_impl(
  after_friends_since timestamptz default null,
  after_friend_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz, has_more boolean,
  total_count integer
)
language plpgsql security definer set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_page_size integer := least(greatest(coalesce(page_size, 50), 1), 50);
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if (after_friends_since is null) <> (after_friend_id is null) then
    raise exception using errcode = '22023', message = 'invalid_friends_cursor';
  end if;
  return query
  with total as materialized (
    select count(*)::integer as value
    from public.friendships friendship
    join public.profiles peer on peer.id = case
      when friendship.user_one_id = current_user_id then friendship.user_two_id
      else friendship.user_one_id end
    where current_user_id in (friendship.user_one_id, friendship.user_two_id)
      and not private.is_account_pending_deletion(peer.id)
  ), limited as materialized (
    select candidates.friend_id, candidates.friends_since
    from (
      select friendship.user_two_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_one_id = current_user_id
        and not private.is_account_pending_deletion(friendship.user_two_id)
        and (after_friends_since is null or friendship.created_at < after_friends_since
          or (friendship.created_at = after_friends_since and friendship.user_two_id < after_friend_id))
      union all
      select friendship.user_one_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_two_id = current_user_id
        and not private.is_account_pending_deletion(friendship.user_one_id)
        and (after_friends_since is null or friendship.created_at < after_friends_since
          or (friendship.created_at = after_friends_since and friendship.user_one_id < after_friend_id))
    ) candidates
    order by candidates.friends_since desc, candidates.friend_id desc
    limit normalized_page_size + 1
  ), page as materialized (
    select * from limited order by friends_since desc, friend_id desc limit normalized_page_size
  )
  select peer.id, peer.username, peer.display_name, peer.avatar_url,
    peer.avatar_storage_path, page.friends_since,
    exists (select 1 from limited offset normalized_page_size), total.value
  from page join public.profiles peer on peer.id = page.friend_id
  cross join total
  order by page.friends_since desc, page.friend_id desc;
end;
$$;

create or replace function public.get_current_friend(target_friend_id uuid)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz, is_online boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friends', 30);
  return query
  select friend.id,
    case when private.is_account_globally_banned(friend.id) then '' else friend.username end,
    case when private.is_account_globally_banned(friend.id)
      then 'Заблокированный пользователь' else friend.display_name end,
    case when private.is_account_globally_banned(friend.id) then null else friend.avatar_url end,
    case when private.is_account_globally_banned(friend.id) then null else friend.avatar_storage_path end,
    friend.friends_since, private.is_user_online(friend.id)
  from private.get_current_friend_impl(target_friend_id) friend
  where not private.is_account_globally_banned(friend.id)
    and not private.is_account_pending_deletion(friend.id)
    and not private.is_blocked_by_impl(friend.id, auth.uid());
end;
$$;

create or replace function public.get_current_friends(target_friend_ids uuid[])
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz, is_online boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friends', 30);
  return query
  select friend.id, friend.username, friend.display_name, friend.avatar_url,
    friend.avatar_storage_path, friend.friends_since, private.is_user_online(friend.id)
  from private.get_current_friends_impl(target_friend_ids) friend
  where not private.is_account_globally_banned(friend.id)
    and not private.is_account_pending_deletion(friend.id)
    and not private.is_blocked_by_impl(friend.id, auth.uid());
end;
$$;

create or replace function public.get_friend_requests()
returns table (
  request_id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, peer_friend_count bigint,
  direction text, requested_at timestamptz
)
language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friend_requests', 30);
  return query
  select request.request_id,
    request.peer_id,
    case when private.is_account_globally_banned(request.peer_id) then '' else request.peer_username end,
    case when private.is_account_globally_banned(request.peer_id)
      then 'Заблокированный пользователь' else request.peer_display_name end,
    case when private.is_account_globally_banned(request.peer_id) then null else request.peer_avatar_url end,
    case when private.is_account_globally_banned(request.peer_id) then null else request.peer_avatar_storage_path end,
    case when private.is_account_globally_banned(request.peer_id) then null else request.peer_friend_count end,
    request.direction, request.requested_at
  from private.get_friend_requests_impl() request
  where not private.is_account_pending_deletion(request.peer_id);
end;
$$;

create or replace function public.get_user_profile_friends(
  target_user_id uuid,
  after_display_name text default null,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, mutual_friend_count integer, has_more boolean
)
language sql security invoker set search_path = ''
as $$
  select friend.id,
    case when private.is_account_globally_banned(friend.id) then '' else friend.username end,
    case when private.is_account_globally_banned(friend.id)
      then 'Заблокированный пользователь' else friend.display_name end,
    case when private.is_account_globally_banned(friend.id) then null else friend.avatar_url end,
    case when private.is_account_globally_banned(friend.id) then null else friend.avatar_storage_path end,
    case when private.is_account_globally_banned(friend.id) then 0 else friend.mutual_friend_count end,
    friend.has_more
  from private.get_user_profile_friends_impl(target_user_id, after_display_name, after_user_id, page_size) friend
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_account_pending_deletion(target_user_id)
    and not private.is_account_pending_deletion(friend.id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

create or replace function public.get_viewed_profile(
  target_user_id uuid,
  should_register_view boolean default true
)
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  photos jsonb, relationship text, request_id uuid, friend_count bigint,
  friends_preview jsonb, profile_view_count bigint, last_seen_at timestamptz,
  shows_last_seen boolean, is_online boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.consume_profile_read_quota(target_user_id);
  if private.is_account_pending_deletion(target_user_id) then
    return query
    select profile.id, ''::text, 'Удалённый пользователь'::text, null::date,
      null::text, null::text, null::timestamptz, ''::text, ''::text,
      true, null::timestamptz, '[]'::jsonb, 'blocked'::text, null::uuid,
      0::bigint, '[]'::jsonb, 0::bigint, null::timestamptz, false, false
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;
  if private.is_account_globally_banned(target_user_id) then
    return query
    select profile.id, ''::text, 'Заблокированный пользователь'::text, null::date,
      null::text, null::text, null::timestamptz, ''::text, ''::text,
      true, null::timestamptz, '[]'::jsonb, 'blocked'::text, null::uuid,
      0::bigint, '[]'::jsonb, 0::bigint, null::timestamptz, false, false
    from public.profiles profile where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;
  if private.is_blocked_by_impl(target_user_id, auth.uid()) then
    if coalesce(should_register_view, true) then
      perform private.record_profile_view_impl(target_user_id);
    else
      perform private.get_profile_view_count_impl(target_user_id);
    end if;
    return query
    select profile.id, ''::text, profile.display_name, null::date,
      null::text, null::text, null::timestamptz, ''::text, ''::text,
      true, null::timestamptz, '[]'::jsonb, 'blocked'::text, null::uuid,
      0::bigint, '[]'::jsonb, 0::bigint, null::timestamptz, false, false
    from public.profiles profile where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;
  return query select profile.*, private.is_user_online(profile.id)
  from private.get_viewed_profile_impl(target_user_id, should_register_view) profile;
end;
$$;

create or replace function public.is_push_message_deliverable(target_message_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.messages message
    where message.id = target_message_id
      and message.deleted_for_everyone_at is null
      and not private.is_account_pending_deletion(message.sender_id)
      and not exists (
        select 1 from public.conversation_members peer
        where peer.conversation_id = message.conversation_id
          and peer.user_id <> message.sender_id
          and (private.is_account_globally_banned(peer.user_id)
            or private.is_account_pending_deletion(peer.user_id)
            or private.is_user_pair_blocked_impl(message.sender_id, peer.user_id))
      )
  );
$$;

create or replace function public.get_friend_location_visibility(friend_user_id uuid)
returns table (
  latitude double precision, longitude double precision, updated_at timestamptz,
  availability text
)
language plpgsql security invoker set search_path = ''
as $$
begin
  if auth.uid() is null
     or friend_user_id is null
     or private.is_account_globally_banned(friend_user_id)
     or private.is_account_pending_deletion(friend_user_id)
     or private.is_blocked_by_impl(friend_user_id, auth.uid()) then
    return;
  end if;

  -- Keep the pre-existing pair quota outside the private implementation.
  -- Replacing the original wrapper with a WHERE clause accidentally bypassed
  -- it for this endpoint.
  perform private.consume_location_distance_read_quota(friend_user_id);
  return query select * from private.get_friend_location_visibility_impl(friend_user_id);
end;
$$;

create or replace function public.get_user_distance(target_user_id uuid)
returns table (
  distance_value integer, distance_unit text, updated_at timestamptz
)
-- This ultimately writes the pair read-quota.  It must remain VOLATILE so
-- PostgREST does not run it in a read-only transaction.
language sql security invoker set search_path = ''
as $$
  select * from private.get_user_distance_impl(target_user_id)
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_account_pending_deletion(target_user_id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

-- Keep the nearby RPC cursor/server cap intact; the outer filter is only a
-- final privacy guard.  A pending-deletion profile is never returned to the
-- device even if its location row still exists until finalisation.
create or replace function public.get_nearby_people(
  preferred_gender text default null,
  minimum_age integer default 18,
  maximum_age integer default 99,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, active_until timestamptz, has_more boolean,
  is_online boolean
)
language sql security invoker set search_path = ''
as $$
  select *
  from private.get_nearby_people_impl(
    preferred_gender, minimum_age, maximum_age, after_user_id, page_size
  ) candidate
  where not private.is_account_pending_deletion(candidate.id);
$$;

create or replace function private.avatar_owner_is_pending_deletion_impl(
  avatar_owner_folder text
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from private.account_deletion_requests request
    where request.target_user_id::text = avatar_owner_folder
      and request.restored_at is null
  );
$$;

drop policy if exists "Users can read non-blocked avatars" on storage.objects;
create policy "Users can read non-blocked avatars"
on storage.objects for select to authenticated
using (
  bucket_id = 'avatars'
  and not private.avatar_owner_blocks_current_viewer_impl((storage.foldername(name))[1])
  and not private.avatar_owner_is_pending_deletion_impl((storage.foldername(name))[1])
);

-- Server-side row security also covers Storage and Realtime, which do not use
-- the PostgREST pre-request guard.
create policy "Deleting accounts cannot access profiles"
on public.profiles as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access profile photos"
on public.profile_photos as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access conversations"
on public.conversations as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access conversation members"
on public.conversation_members as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access messages"
on public.messages as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access message attachments"
on public.message_attachments as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access message receipts"
on public.message_receipts as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access hidden messages"
on public.message_hidden_for_users as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access friendships"
on public.friendships as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access friend requests"
on public.friend_requests as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access user blocks"
on public.user_blocks as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access locations"
on public.user_locations as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access push devices"
on public.push_devices as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot access storage"
on storage.objects as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));
create policy "Deleting accounts cannot use realtime"
on realtime.messages as restrictive for all to authenticated
using (not private.is_account_pending_deletion((select auth.uid())))
with check (not private.is_account_pending_deletion((select auth.uid())));

revoke all on function private.is_account_pending_deletion(uuid)
  from public, anon;
revoke all on function private.request_account_deletion_impl(uuid, text, text, interval)
  from public, anon, authenticated;
revoke all on function private.restore_account_deletion_impl(uuid)
  from public, anon, authenticated;
revoke all on function private.finalize_due_account_deletions(integer)
  from public, anon, authenticated;
revoke all on function public.request_account_deletion_from_service(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.restore_account_deletion_from_service(uuid)
  from public, anon, authenticated;
revoke all on function private.get_my_account_access_impl()
  from public, anon;
revoke all on function public.get_my_account_access()
  from public, anon;
revoke all on function private.get_chat_summaries_rate_limited_impl()
  from public, anon;
revoke all on function public.get_chat_summaries()
  from public, anon;
revoke all on function private.apply_account_deletion_request_change()
  from public, anon, authenticated;
revoke all on function private.avatar_owner_is_pending_deletion_impl(text)
  from public, anon, authenticated;

grant execute on function private.is_account_pending_deletion(uuid)
  to authenticated, service_role;
grant execute on function private.request_account_deletion_impl(uuid, text, text, interval)
  to service_role;
grant execute on function private.restore_account_deletion_impl(uuid)
  to service_role;
grant execute on function private.finalize_due_account_deletions(integer)
  to service_role;
grant execute on function public.request_account_deletion_from_service(uuid, text, text)
  to service_role;
grant execute on function public.restore_account_deletion_from_service(uuid)
  to service_role;
grant execute on function private.get_my_account_access_impl()
  to authenticated, service_role;
grant execute on function public.get_my_account_access()
  to authenticated, service_role;
grant execute on function private.get_chat_summaries_rate_limited_impl()
  to authenticated, service_role;
grant execute on function public.get_chat_summaries()
  to authenticated, service_role;
grant execute on function private.apply_account_deletion_request_change()
  to service_role;
grant execute on function private.avatar_owner_is_pending_deletion_impl(text)
  to authenticated, service_role;

do $$
begin
  if to_regclass('cron.job') is not null then
    execute $schedule$
      select cron.schedule(
        'finalize-due-account-deletions',
        '20 3 * * *',
        'select private.finalize_due_account_deletions()'
      )
      where not exists (
        select 1 from cron.job
        where jobname = 'finalize-due-account-deletions'
      )
    $schedule$;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping account deletion cron; schedule it with database owner privileges';
end;
$$;

notify pgrst, 'reload schema';
