-- Existing public RPC signatures are preserved, direct writes cannot bypass
-- their guards. Private implementations follow the project's invoker pattern.
alter table public.push_devices add column registered_at timestamptz;
update public.push_devices set registered_at = created_at;
alter table public.push_devices alter column registered_at set default now(),
  alter column registered_at set not null;
revoke insert, update, delete on public.push_devices from public, anon, authenticated;
-- Preserve pre-existing excess rows; only stop sending to the older tokens.
update public.push_devices set enabled=false where id in (
  select id from (
    select id, row_number() over (partition by user_id order by last_seen_at desc, id desc) as position
    from public.push_devices
  ) ranked where position > 10
);
create table private.push_device_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0)
);
revoke all on private.push_device_write_limits from public, anon, authenticated;

create or replace function private.register_push_device_impl(device_token text, device_locale text, device_app_version text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid(); normalized_token text := trim(device_token);
  saved_language text; current_count integer;
  registered_time timestamptz := statement_timestamp();
begin
  if owner_id is null then raise exception 'authentication_required'; end if;
  perform private.require_active_account();
  if normalized_token is null or length(normalized_token) not between 20 and 4096 then
    raise exception 'invalid_push_token';
  end if;
  if length(coalesce(device_app_version, '')) > 100 then
    raise exception 'invalid_app_version' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('push-devices:' || owner_id::text, 0));
  insert into private.push_device_write_limits as limits values (owner_id, registered_time, 1)
  on conflict (user_id) do update set
    window_started_at = case when limits.window_started_at <= registered_time - interval '1 minute'
      then registered_time else limits.window_started_at end,
    request_count = case when limits.window_started_at <= registered_time - interval '1 minute'
      then 1 else limits.request_count + 1 end
  returning request_count into current_count;
  if current_count > 60 then raise exception 'push_device_rate_limited' using errcode = '42901'; end if;
  saved_language := private.get_current_app_language_for_push_impl();
  insert into public.push_devices as device (
    user_id, token, platform, locale, app_version, enabled, updated_at, last_seen_at, registered_at
  ) values (
    owner_id, normalized_token, 'android',
    case when saved_language in ('ru','en') then saved_language
      when lower(trim(coalesce(device_locale,''))) = 'en' then 'en' else 'ru' end,
    nullif(trim(coalesce(device_app_version,'')),''), true, registered_time, registered_time, registered_time
  ) on conflict (token) do update set
    user_id = excluded.user_id, locale = excluded.locale, app_version = excluded.app_version,
    enabled = true, updated_at = excluded.updated_at, last_seen_at = excluded.last_seen_at,
    registered_at = case when device.user_id = excluded.user_id
      then device.registered_at else excluded.registered_at end;
  -- Preserve the existing normal registration/eviction workflow, now serialized.
  -- Recheck ownership on the target row too: a transfer may commit while this
  -- DELETE waits for its row lock after selecting IDs from an older snapshot.
  delete from public.push_devices where user_id = owner_id and id in (
    select id from public.push_devices where user_id = owner_id
    order by last_seen_at desc, id desc offset 10
  );
end; $$;

create function private.unregister_push_device_impl(device_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  perform private.require_active_account();
  delete from public.push_devices where user_id = auth.uid() and token = trim(device_token);
end; $$;
create or replace function public.register_push_device(device_token text, device_locale text default 'ru', device_app_version text default null)
returns void language sql security invoker set search_path = '' as $$
  select private.register_push_device_impl(device_token, device_locale, device_app_version);
$$;
create or replace function public.unregister_push_device(device_token text)
returns void language sql security invoker set search_path = '' as $$
  select private.unregister_push_device_impl(device_token);
$$;
revoke all on function private.register_push_device_impl(text,text,text), private.unregister_push_device_impl(text) from public, anon;
grant execute on function private.register_push_device_impl(text,text,text), private.unregister_push_device_impl(text) to authenticated;

alter table public.push_notification_outbox
  add column expires_at timestamptz,
  add column next_attempt_at timestamptz not null default now(),
  add column lease_until timestamptz,
  add column claim_token uuid,
  add column accepted_device_ids uuid[] not null default '{}',
  add column completed_device_ids uuid[] not null default '{}',
  add column has_permanent_failure boolean not null default false;
update public.push_notification_outbox set expires_at = least(created_at, message_created_at) + interval '24 hours';
alter table public.push_notification_outbox alter column expires_at set default (now() + interval '24 hours'), alter column expires_at set not null;
alter table public.push_notification_outbox drop constraint push_notification_outbox_delivery_result_check;
alter table public.push_notification_outbox add constraint push_notification_outbox_delivery_result_check
  check (delivery_result in ('delivered_to_fcm','no_devices','message_deleted','expired'));
create index push_outbox_due_idx on public.push_notification_outbox(next_attempt_at, id) where status = 'pending';
-- Replaced by the due index; do not maintain a second old pending index.
drop index public.push_notification_outbox_pending_idx;
create index push_outbox_lease_idx on public.push_notification_outbox(lease_until, id) where status = 'processing';
create index push_outbox_processed_idx on public.push_notification_outbox(processed_at, id) where status in ('sent','failed');
-- Old in-flight jobs also recover. A crash after FCM acceptance but before its
-- DB checkpoint still has unavoidable at-least-once delivery semantics.
update public.push_notification_outbox set lease_until = now() where status = 'processing';

create function private.is_push_job_deliverable(job public.push_notification_outbox)
returns boolean language sql stable security definer set search_path = '' as $$
  select not private.is_account_globally_banned(job.recipient_user_id)
    and not private.is_account_pending_deletion(job.recipient_user_id)
    and not private.is_account_globally_banned(job.sender_id)
    and not private.is_account_pending_deletion(job.sender_id)
    and not private.is_user_pair_blocked_impl(job.sender_id, job.recipient_user_id)
    and case job.notification_type
      when 'friend_request' then exists (
        select 1 from public.friend_requests r where r.id = job.friend_request_id
          and r.sender_id = job.sender_id and r.recipient_id = job.recipient_user_id)
      when 'message_reaction' then public.is_push_reaction_deliverable(job.reaction_message_id, job.sender_id, job.reaction_code)
      else public.is_push_message_deliverable(job.message_id) and exists (
        select 1 from public.conversation_members cm join public.messages m on m.id = job.message_id
        where cm.conversation_id = job.conversation_id and cm.user_id = job.recipient_user_id
          and not cm.is_muted and m.created_at > coalesce(cm.cleared_at, '-infinity'::timestamptz)
          and not exists (select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=cm.user_id)
      ) end;
$$;
revoke all on function private.is_push_job_deliverable(public.push_notification_outbox) from public, anon, authenticated;

create function public.claim_push_notification(outbox_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare job public.push_notification_outbox%rowtype; devices jsonb; stop_reason text;
begin
  select * into job from public.push_notification_outbox o where o.id = outbox_id
    and ((o.status='pending' and o.next_attempt_at<=statement_timestamp())
      or (o.status='processing' and o.lease_until<=statement_timestamp())) for update skip locked;
  if job.id is null then return jsonb_build_object('status','already_processed'); end if;
  if job.expires_at<=statement_timestamp() then stop_reason := 'expired';
  elsif job.attempts>=8 then
    update public.push_notification_outbox set status='failed', processed_at=statement_timestamp(),
      lease_until=null, claim_token=null, last_error='retry_limit_exceeded' where id=job.id;
    return jsonb_build_object('status','failed');
  elsif not private.is_push_job_deliverable(job) then stop_reason := 'message_deleted'; end if;
  if stop_reason is null then
    select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'token',d.token)),'[]') into devices
    from (select id,token from public.push_devices where user_id=job.recipient_user_id and enabled
      and registered_at<=job.created_at and not (id=any(job.completed_device_ids))
      order by last_seen_at desc,id desc limit 10) d;
    if jsonb_array_length(devices)=0 then
      stop_reason := case when cardinality(job.accepted_device_ids)>0 then 'delivered_to_fcm' else 'no_devices' end;
    end if;
  end if;
  if stop_reason is not null then
    update public.push_notification_outbox set
      status=case when has_permanent_failure and stop_reason<>'expired' then 'failed' else 'sent' end,
      processed_at=statement_timestamp(), delivery_result=stop_reason,
      delivered_device_count=cardinality(accepted_device_ids), lease_until=null, claim_token=null where id=job.id;
    return jsonb_build_object('status',stop_reason);
  end if;
  update public.push_notification_outbox set status='processing', attempts=attempts+1,
    claim_token=gen_random_uuid(), lease_until=statement_timestamp()+interval '2 minutes',
    processed_at=null where id=job.id returning * into job;
  return jsonb_build_object('job',to_jsonb(job),'devices',devices);
end; $$;

create function public.finish_push_notification(outbox_id uuid, lease_token uuid, device_results jsonb,
  retry_delay_seconds integer default 60, failure_reason text default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare job public.push_notification_outbox%rowtype; result jsonb; device_id uuid; needs_retry boolean := false;
begin
  if device_results is null or jsonb_typeof(device_results)<>'array' or jsonb_array_length(device_results)>10 then
    raise exception 'invalid_delivery_results' using errcode='22023'; end if;
  select * into job from public.push_notification_outbox o
    where o.id=outbox_id and o.status='processing' and o.claim_token=lease_token for update;
  if job.id is null then return jsonb_build_object('status','lease_lost'); end if;
  for result in select value from jsonb_array_elements(device_results) loop
    device_id := (result->>'device_id')::uuid;
    if device_id is null or result->>'token' is null then
      raise exception 'invalid_delivery_device' using errcode='22023'; end if;
    if result->>'outcome' not in ('accepted','invalid','retry','failed') or result->>'outcome' is null then
      raise exception 'invalid_delivery_outcome' using errcode='22023'; end if;
    if result->>'outcome'='retry' then needs_retry := true;
    else
      if not (device_id=any(job.completed_device_ids)) then job.completed_device_ids := array_append(job.completed_device_ids,device_id); end if;
      if result->>'outcome'='accepted' and not (device_id=any(job.accepted_device_ids)) then
        job.accepted_device_ids := array_append(job.accepted_device_ids,device_id);
      elsif result->>'outcome'='failed' then job.has_permanent_failure := true;
      elsif result->>'outcome'='invalid' then
        update public.push_devices set enabled=false, updated_at=statement_timestamp()
          where id=device_id and user_id=job.recipient_user_id and token=result->>'token' and registered_at<=job.created_at;
      end if;
    end if;
  end loop;
  if jsonb_array_length(device_results)=0 then needs_retry := true; end if;
  update public.push_notification_outbox set
    accepted_device_ids=job.accepted_device_ids, completed_device_ids=job.completed_device_ids,
    has_permanent_failure=job.has_permanent_failure, delivered_device_count=cardinality(job.accepted_device_ids),
    last_error=left(failure_reason,2000), lease_until=null, claim_token=null,
    next_attempt_at=statement_timestamp()+make_interval(secs=>greatest(60,least(coalesce(retry_delay_seconds,60),86400))),
    status=case when job.expires_at<=statement_timestamp() then 'sent'
      when needs_retry and job.attempts<8 then 'pending'
      when needs_retry or job.has_permanent_failure then 'failed' else 'sent' end,
    processed_at=case when needs_retry and job.attempts<8 and job.expires_at>statement_timestamp()
      then null else statement_timestamp() end,
    delivery_result=case when job.expires_at<=statement_timestamp() then 'expired'
      when needs_retry then null when cardinality(job.accepted_device_ids)>0 then 'delivered_to_fcm' else 'no_devices' end
  where id=job.id returning * into job;
  return jsonb_build_object('status',job.status,'devices',job.delivered_device_count);
end; $$;

create or replace function public.get_due_push_notification_ids(batch_size integer default 20)
returns jsonb language sql stable security invoker set search_path = '' as $$
  -- Each partial index supplies at most 20 rows; sort <=40 candidates rather
  -- than every due row when a large backlog accumulates during an outage.
  select coalesce(jsonb_agg(id),'[]') from (
    select id from (
      (select id,next_attempt_at as due_at from public.push_notification_outbox
        where status='pending' and next_attempt_at<=statement_timestamp()
        order by next_attempt_at,id limit 20)
      union all
      (select id,lease_until as due_at from public.push_notification_outbox
        where status='processing' and lease_until<=statement_timestamp()
        order by lease_until,id limit 20)
    ) candidates order by due_at,id
    limit greatest(1,least(coalesce(batch_size,20),20))
  ) due;
$$;
revoke all on function public.claim_push_notification(uuid), public.finish_push_notification(uuid,uuid,jsonb,integer,text),
  public.get_due_push_notification_ids(integer) from public, anon, authenticated;
grant execute on function public.claim_push_notification(uuid), public.finish_push_notification(uuid,uuid,jsonb,integer,text),
  public.get_due_push_notification_ids(integer), private.is_push_job_deliverable(public.push_notification_outbox) to service_role;

-- User-authorized bounded removal of terminal delivery history, NOT messages.
create function private.cleanup_push_notification_outbox(batch_size integer default 5000)
returns integer language plpgsql security definer set search_path = '' as $$
declare removed integer;
begin
  with candidates as (select id from public.push_notification_outbox
    where status in ('sent','failed') and processed_at<statement_timestamp()-interval '7 days'
    order by processed_at,id limit greatest(1,least(coalesce(batch_size,5000),5000)) for update skip locked
  ) delete from public.push_notification_outbox where id in (select id from candidates);
  get diagnostics removed = row_count;
  return removed;
end; $$;
revoke all on function private.cleanup_push_notification_outbox(integer) from public,anon,authenticated;

-- No external request when idle. One bounded recovery batch each minute.
do $$ begin
  if to_regclass('cron.job') is not null then
    perform cron.schedule('retry-push-notifications','* * * * *',$job$
      select net.http_post(url:=config.url || '/functions/v1/push-message',
        headers:=jsonb_build_object('Content-Type','application/json','x-webhook-secret',config.secret),
        body:='{"retry_due":true}'::jsonb, timeout_milliseconds:=120000)
      from (select max(decrypted_secret) filter(where name='push_delivery_project_url') as url,
        max(decrypted_secret) filter(where name='push_delivery_webhook_secret') as secret
        from vault.decrypted_secrets where name in ('push_delivery_project_url','push_delivery_webhook_secret')) config
      where config.url is not null and config.secret is not null and exists(select 1 from public.push_notification_outbox where
        (status='pending' and next_attempt_at<=now()) or (status='processing' and lease_until<=now()));
    $job$);
    perform cron.schedule('cleanup-push-notification-outbox','49 * * * *',
      'select private.cleanup_push_notification_outbox(5000)');
  end if;
end; $$;
notify pgrst,'reload schema';
