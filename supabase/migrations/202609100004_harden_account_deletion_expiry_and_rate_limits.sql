-- Keep the recovery screen truthful once its deadline has passed, throttle
-- Edge Function actions, and drain finalisation work steadily instead of in
-- a small daily batch.

create table private.account_deletion_action_rate_limits (
  target_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in ('request', 'restore')),
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 0 check (request_count >= 0),
  primary key (target_user_id, action)
);

create or replace function private.consume_account_deletion_action_quota(
  target_account_user_id uuid,
  requested_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  accepted_count integer;
begin
  if target_account_user_id is null
     or requested_action not in ('request', 'restore') then
    raise exception using errcode = '22023', message = 'invalid_account_deletion_action';
  end if;

  insert into private.account_deletion_action_rate_limits as limits (
    target_user_id, action, window_started_at, request_count
  ) values (
    target_account_user_id, requested_action, statement_timestamp(), 1
  )
  on conflict on constraint account_deletion_action_rate_limits_pkey do update
  set
    window_started_at = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then statement_timestamp()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then 1
      else limits.request_count + 1
    end
  where limits.window_started_at <= statement_timestamp() - interval '1 minute'
     or limits.request_count < 10
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'account_deletion_rate_limited';
  end if;
end;
$$;

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
  normalized_requester text := coalesce(nullif(btrim(requested_by_value), ''), 'self');
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

  -- Administrator inserts remain available for moderation. Every user-facing
  -- Edge request, including an idempotent repeat, is capped at ten/minute.
  if normalized_requester = 'self' then
    perform private.consume_account_deletion_action_quota(target_account_user_id, 'request');
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

  if normalized_requester = 'self'
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
    normalized_requester,
    nullif(btrim(requested_note), '')
  )
  returning * into existing_request;

  return query select existing_request.scheduled_for;
end;
$$;

drop function if exists public.get_my_account_access();
drop function if exists private.get_my_account_access_impl();

create function private.get_my_account_access_impl()
returns table (
  is_banned boolean,
  is_deletion_pending boolean,
  is_deletion_expired boolean,
  deletion_scheduled_for timestamptz,
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
    private.is_account_globally_banned(account.user_id) or flags.finalized,
    private.is_account_pending_deletion(account.user_id)
      and not flags.finalized
      and not flags.expired,
    flags.expired,
    deletion.scheduled_for,
    profile.username,
    content.support_email
  from (select auth.uid() as user_id) account
  left join lateral (
    select request.scheduled_for
    from private.account_deletion_requests request
    where request.target_user_id = account.user_id
      and request.restored_at is null
      and request.finalized_at is null
    order by request.requested_at desc
    limit 1
  ) deletion on true
  cross join lateral (
    select
      exists (
        select 1
        from private.account_deletion_requests request
        where request.target_user_id = account.user_id
          and request.restored_at is null
          and request.finalized_at is not null
      ) as finalized,
      deletion.scheduled_for is not null
        and deletion.scheduled_for <= statement_timestamp() as expired
  ) flags
  left join public.profiles profile on profile.id = account.user_id
  left join private.app_public_content content on content.singleton;
end;
$$;

create function public.get_my_account_access()
returns table (
  is_banned boolean,
  is_deletion_pending boolean,
  is_deletion_expired boolean,
  deletion_scheduled_for timestamptz,
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

create or replace function public.restore_account_deletion_from_service(
  target_user_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_account_deletion_action_quota(target_user_id, 'restore');
  perform private.restore_account_deletion_impl(target_user_id);
end;
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

revoke all on function private.consume_account_deletion_action_quota(uuid, text)
  from public, anon, authenticated;
revoke all on function private.get_my_account_access_impl() from public, anon;
revoke all on function public.get_my_account_access() from public, anon;
grant execute on function private.consume_account_deletion_action_quota(uuid, text)
  to service_role;
grant execute on function private.get_my_account_access_impl()
  to authenticated, service_role;
grant execute on function public.get_my_account_access()
  to authenticated, service_role;

do $$
declare
  existing_job_id bigint;
begin
  if to_regclass('cron.job') is not null then
    select jobid into existing_job_id
    from cron.job
    where jobname = 'finalize-due-account-deletions';

    if existing_job_id is null then
      perform cron.schedule(
        'finalize-due-account-deletions',
        '17 * * * *',
        'select private.finalize_due_account_deletions(50)'
      );
    else
      perform cron.alter_job(
        existing_job_id,
        schedule => '17 * * * *',
        command => 'select private.finalize_due_account_deletions(50)'
      );
    end if;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping account deletion cron update; update it with database owner privileges';
end;
$$;

notify pgrst, 'reload schema';
