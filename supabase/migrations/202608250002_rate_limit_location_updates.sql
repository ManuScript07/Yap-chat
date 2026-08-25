-- Keep location writes bounded even when update_my_location is called by a
-- modified or malfunctioning client. The conflict predicate is evaluated
-- while PostgreSQL holds the target row lock, so concurrent calls cannot
-- bypass the cooldown.
create or replace function private.update_my_location_impl(
  new_latitude double precision,
  new_longitude double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  if new_latitude not between -90 and 90
     or new_longitude not between -180 and 180 then
    raise exception 'invalid_location';
  end if;

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
                    radians(
                      excluded.longitude - current_location.longitude
                    ) / 2.0
                  ),
                  2.0
                )
            )
          )
        )
      ) >= 100.0
    );
end;
$$;

revoke all on function private.update_my_location_impl(
  double precision,
  double precision
) from public, anon;

grant execute on function private.update_my_location_impl(
  double precision,
  double precision
) to authenticated, service_role;

comment on function private.update_my_location_impl(
  double precision,
  double precision
) is
  'Atomically rate-limits tracked location writes to one per minute and only after 100 m movement or 12 hours.';
