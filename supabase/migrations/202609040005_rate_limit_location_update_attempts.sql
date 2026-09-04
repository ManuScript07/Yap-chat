-- The write cooldown below protects the location itself, but a modified
-- client could still repeatedly invoke the public RPCs. Count attempts before
-- entering the write path so all current and released update wrappers share a
-- small, atomic per-account ceiling.
create table if not exists private.location_update_attempt_limits (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.location_update_attempt_limits
  from public, anon, authenticated;

create or replace function private.consume_location_update_attempt_quota()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.location_update_attempt_limits as limits (
    user_id,
    window_started_at,
    request_count
  ) values (
    current_user_id,
    statement_timestamp(),
    1
  )
  on conflict (user_id) do update
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
    raise exception using errcode = '42901', message = 'location_update_rate_limited';
  end if;
end;
$$;

-- Both legacy RPCs and update_my_location_with_metadata delegate to this
-- implementation, so one check covers every publicly callable write path.
create or replace function private.update_my_location_impl(
  new_latitude double precision,
  new_longitude double precision
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare did_update boolean;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  perform private.consume_location_update_attempt_quota();

  if new_latitude not between -90 and 90
     or new_longitude not between -180 and 180 then
    raise exception using errcode = '22023', message = 'invalid_location';
  end if;

  with updated as (
    insert into public.user_locations as current_location (
      user_id,
      latitude,
      longitude,
      updated_at
    )
    values (
      auth.uid(),
      new_latitude,
      new_longitude,
      statement_timestamp()
    )
    on conflict (user_id) do update
    set latitude = excluded.latitude,
        longitude = excluded.longitude,
        updated_at = excluded.updated_at
    where current_location.updated_at
            <= statement_timestamp() - interval '60 seconds'
      and (
        current_location.updated_at
          <= statement_timestamp() - interval '12 hours'
        or 6371000.0 * 2.0 * asin(
          sqrt(
            least(
              1.0,
              greatest(
                0.0,
                power(
                  sin(
                    radians(excluded.latitude - current_location.latitude) / 2.0
                  ),
                  2.0
                )
                + cos(radians(current_location.latitude))
                  * cos(radians(excluded.latitude))
                  * power(
                    sin(
                      radians(excluded.longitude - current_location.longitude) / 2.0
                    ),
                    2.0
                  )
              )
            )
          )
        ) >= 100.0
      )
    returning 1
  )
  select exists (select 1 from updated) into did_update;

  return did_update;
end;
$$;

revoke all on function private.consume_location_update_attempt_quota()
  from public, anon, authenticated;
revoke all on function private.update_my_location_impl(
  double precision,
  double precision
) from public, anon;

grant execute on function private.update_my_location_impl(
  double precision,
  double precision
) to authenticated, service_role;

comment on function private.consume_location_update_attempt_quota() is
  'Atomically limits location-update RPC attempts to ten per authenticated user per minute.';

comment on function private.update_my_location_impl(
  double precision,
  double precision
) is
  'Enforces ten update attempts per minute, then the 60-second, 100-metre, and 12-hour write guards.';

notify pgrst, 'reload schema';
