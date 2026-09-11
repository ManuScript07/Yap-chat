-- Physically remove profile media only after the irreversible account
-- finalisation. Storage objects must be deleted through the Storage API, not
-- by deleting storage.objects rows from SQL.

create table private.finalized_profile_media_cleanup_queue (
  id uuid primary key default extensions.gen_random_uuid(),
  deletion_request_id uuid not null references private.account_deletion_requests(id)
    on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  bucket_id text not null default 'avatars' check (bucket_id = 'avatars'),
  storage_path text not null,
  queued_at timestamptz not null default statement_timestamp(),
  last_attempt_at timestamptz,
  next_attempt_at timestamptz not null default statement_timestamp(),
  lease_expires_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  deleted_at timestamptz,
  unique (bucket_id, storage_path),
  check (storage_path like owner_user_id::text || '/%')
);

create index finalized_profile_media_cleanup_queue_due_idx
  on private.finalized_profile_media_cleanup_queue (
    next_attempt_at, queued_at, id
  )
  where deleted_at is null;

revoke all on table private.finalized_profile_media_cleanup_queue
  from public, anon, authenticated;

comment on table private.finalized_profile_media_cleanup_queue is
  'Durable service-only queue for physically deleting Storage avatars after an account deletion is finalised.';

create function private.enqueue_finalized_profile_media_cleanup(
  target_deletion_request_id uuid,
  target_owner_user_id uuid
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.finalized_profile_media_cleanup_queue (
    deletion_request_id,
    owner_user_id,
    bucket_id,
    storage_path
  )
  select
    target_deletion_request_id,
    target_owner_user_id,
    'avatars',
    candidate.storage_path
  from (
    select profile.avatar_storage_path as storage_path
    from public.profiles profile
    where profile.id = target_owner_user_id

    union

    select photo.storage_path
    from public.profile_photos photo
    where photo.profile_id = target_owner_user_id
  ) candidate
  where candidate.storage_path is not null
    -- Do not let malformed historical metadata delete another user's file.
    and candidate.storage_path like target_owner_user_id::text || '/%'
  on conflict (bucket_id, storage_path) do nothing;
$$;

create or replace function private.finalize_due_account_deletions(
  maximum_accounts integer default 50
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row record;
  normalized_maximum integer := least(greatest(coalesce(maximum_accounts, 50), 1), 100);
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

    -- Capture all owned avatar paths before profile metadata is removed. The
    -- Edge Function later calls the Storage API with a service key.
    perform private.enqueue_finalized_profile_media_cleanup(
      request_row.id,
      request_row.target_user_id
    );

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
    set username = 'deleted_' || left(md5(request_row.target_user_id::text), 16),
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

create function private.claim_finalized_profile_media_cleanup_batch(
  requested_batch_size integer default 250
)
returns table (
  id uuid,
  owner_user_id uuid,
  bucket_id text,
  storage_path text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_batch_size integer := least(greatest(coalesce(requested_batch_size, 250), 1), 250);
begin
  return query
  with due as (
    select queue.id
    from private.finalized_profile_media_cleanup_queue queue
    where queue.deleted_at is null
      and queue.next_attempt_at <= statement_timestamp()
      and (queue.lease_expires_at is null or queue.lease_expires_at <= statement_timestamp())
    order by queue.next_attempt_at, queue.queued_at, queue.id
    limit normalized_batch_size
    for update skip locked
  ), claimed as (
    update private.finalized_profile_media_cleanup_queue queue
    set attempts = queue.attempts + 1,
        last_attempt_at = statement_timestamp(),
        lease_expires_at = statement_timestamp() + interval '10 minutes'
    from due
    where queue.id = due.id
    returning queue.id, queue.owner_user_id, queue.bucket_id, queue.storage_path
  )
  select claimed.id, claimed.owner_user_id, claimed.bucket_id, claimed.storage_path
  from claimed
  order by claimed.id;
end;
$$;

create function private.complete_finalized_profile_media_cleanup(
  queue_ids uuid[]
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.finalized_profile_media_cleanup_queue queue
  set deleted_at = statement_timestamp(),
      lease_expires_at = null,
      next_attempt_at = statement_timestamp(),
      last_error = null
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[]))
    and queue.deleted_at is null;
$$;

create function private.defer_finalized_profile_media_cleanup(
  queue_ids uuid[],
  failure_message text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.finalized_profile_media_cleanup_queue queue
  set lease_expires_at = null,
      next_attempt_at = statement_timestamp() + least(
        (2 ^ least(queue.attempts, 10)) * interval '1 minute',
        interval '24 hours'
      ),
      last_error = coalesce(nullif(left(btrim(failure_message), 500), ''), 'storage_cleanup_failed')
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[]))
    and queue.deleted_at is null;
$$;

create function public.claim_finalized_profile_media_cleanup_batch(
  requested_batch_size integer default 250
)
returns table (
  id uuid,
  owner_user_id uuid,
  bucket_id text,
  storage_path text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.claim_finalized_profile_media_cleanup_batch(requested_batch_size);
$$;

create function public.complete_finalized_profile_media_cleanup(
  queue_ids uuid[]
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.complete_finalized_profile_media_cleanup(queue_ids);
$$;

create function public.defer_finalized_profile_media_cleanup(
  queue_ids uuid[],
  failure_message text
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.defer_finalized_profile_media_cleanup(queue_ids, failure_message);
$$;

revoke all on function private.enqueue_finalized_profile_media_cleanup(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.claim_finalized_profile_media_cleanup_batch(integer)
  from public, anon, authenticated;
revoke all on function private.complete_finalized_profile_media_cleanup(uuid[])
  from public, anon, authenticated;
revoke all on function private.defer_finalized_profile_media_cleanup(uuid[], text)
  from public, anon, authenticated;
revoke all on function public.claim_finalized_profile_media_cleanup_batch(integer)
  from public, anon, authenticated;
revoke all on function public.complete_finalized_profile_media_cleanup(uuid[])
  from public, anon, authenticated;
revoke all on function public.defer_finalized_profile_media_cleanup(uuid[], text)
  from public, anon, authenticated;

grant execute on function private.enqueue_finalized_profile_media_cleanup(uuid, uuid)
  to service_role;
grant execute on function private.claim_finalized_profile_media_cleanup_batch(integer)
  to service_role;
grant execute on function private.complete_finalized_profile_media_cleanup(uuid[])
  to service_role;
grant execute on function private.defer_finalized_profile_media_cleanup(uuid[], text)
  to service_role;
grant execute on function public.claim_finalized_profile_media_cleanup_batch(integer)
  to service_role;
grant execute on function public.complete_finalized_profile_media_cleanup(uuid[])
  to service_role;
grant execute on function public.defer_finalized_profile_media_cleanup(uuid[], text)
  to service_role;

-- The cron job is inert until these two values are placed in Supabase Vault:
-- account_deletion_cleanup_project_url and
-- account_deletion_cleanup_service_role_key. Secrets never enter a migration.
do $$
declare
  existing_job_id bigint;
  cleanup_command text := $job$
    select net.http_post(
      url := config.project_url || '/functions/v1/cleanup-finalized-profile-media',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', config.service_role_key
      ),
      body := '{}'::jsonb
    )
    from (
      select
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_project_url'
        ) as project_url,
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_service_role_key'
        ) as service_role_key
      from vault.decrypted_secrets secret
      where secret.name in (
        'account_deletion_cleanup_project_url',
        'account_deletion_cleanup_service_role_key'
      )
    ) config
    where config.project_url is not null
      and config.service_role_key is not null;
  $job$;
begin
  if to_regclass('cron.job') is not null then
    select jobid into existing_job_id
    from cron.job
    where jobname = 'cleanup-finalized-profile-media';

    if existing_job_id is null then
      perform cron.schedule(
        'cleanup-finalized-profile-media',
        '23 * * * *',
        cleanup_command
      );
    else
      perform cron.alter_job(
        existing_job_id,
        schedule => '23 * * * *',
        command => cleanup_command
      );
    end if;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping profile-media cleanup cron update; update it with database owner privileges';
end;
$$;

notify pgrst, 'reload schema';
