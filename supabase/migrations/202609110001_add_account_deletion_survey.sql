-- Keep self-service deletion feedback auditable without constraining
-- moderation/admin deletion requests that predate this survey.

alter table private.account_deletion_requests
  add column deletion_reasons text[],
  add column deletion_feedback text,
  add constraint account_deletion_requests_feedback_length
    check (deletion_feedback is null or char_length(deletion_feedback) <= 150);

-- The old three-argument bridge stays available to service-role-only legacy
-- administration. The Edge Function uses this four-argument contract, which
-- makes a survey mandatory for every new self-service request.
create function private.request_account_deletion_with_survey_impl(
  target_account_user_id uuid,
  requested_by_value text default 'self',
  requested_reasons text[] default null,
  requested_feedback text default null,
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
  normalized_feedback text := nullif(btrim(requested_feedback), '');
  allowed_reasons constant text[] := array[
    'ads', 'new_account', 'safety', 'few_people', 'no_longer_chat',
    'technical_problems', 'other'
  ];
begin
  if target_account_user_id is null then
    raise exception using errcode = '22023', message = 'invalid_deletion_target';
  end if;
  if normalized_retention < interval '1 minute' or normalized_retention > interval '90 days' then
    raise exception using errcode = '22023', message = 'invalid_deletion_retention';
  end if;

  if normalized_requester = 'self' then
    if requested_reasons is null
       or cardinality(requested_reasons) = 0
       or cardinality(requested_reasons) > cardinality(allowed_reasons)
       or exists (
         select 1
         from unnest(requested_reasons) as reason(value)
         where reason.value is null or reason.value <> all(allowed_reasons)
       )
       or (select count(distinct reason.value) from unnest(requested_reasons) as reason(value))
          <> cardinality(requested_reasons)
       or (normalized_feedback is not null and char_length(normalized_feedback) > 150) then
      raise exception using errcode = '22023', message = 'account_deletion_survey_invalid';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account-deletion:' || target_account_user_id::text, 0)
  );

  if not exists (select 1 from auth.users user_row where user_row.id = target_account_user_id) then
    raise exception using errcode = 'P0002', message = 'account_not_found';
  end if;

  -- A globally banned identity must retain its moderation state. Administrators
  -- can still schedule deletion directly when needed.
  if normalized_requester = 'self'
     and private.is_account_globally_banned(target_account_user_id) then
    raise exception using errcode = 'P0001', message = 'account_globally_banned';
  end if;

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
    target_user_id,
    scheduled_for,
    requested_by,
    note,
    deletion_reasons,
    deletion_feedback
  ) values (
    target_account_user_id,
    statement_timestamp() + normalized_retention,
    normalized_requester,
    nullif(btrim(requested_note), ''),
    case when normalized_requester = 'self' then requested_reasons else null end,
    case when normalized_requester = 'self' then normalized_feedback else null end
  ) returning * into existing_request;

  return query select existing_request.scheduled_for;
end;
$$;

create function public.request_account_deletion_from_service(
  target_user_id uuid,
  requested_by_value text,
  requested_reasons text[],
  requested_feedback text default null
)
returns table (scheduled_for timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from private.request_account_deletion_with_survey_impl(
    target_user_id,
    requested_by_value,
    requested_reasons,
    requested_feedback,
    null,
    interval '30 days'
  );
$$;

revoke all on function private.request_account_deletion_with_survey_impl(uuid, text, text[], text, text, interval)
  from public, anon, authenticated;
revoke all on function public.request_account_deletion_from_service(uuid, text, text[], text)
  from public, anon, authenticated;
grant execute on function private.request_account_deletion_with_survey_impl(uuid, text, text[], text, text, interval)
  to service_role;
grant execute on function public.request_account_deletion_from_service(uuid, text, text[], text)
  to service_role;

notify pgrst, 'reload schema';
