-- A client must not advance its local location cache when the server rejects
-- an update during the 60-second write cooldown. Keep the existing void RPC
-- for released clients and expose a result-bearing companion for new ones.
drop function public.update_my_location(double precision, double precision);
drop function private.update_my_location_impl(double precision, double precision);

create function private.update_my_location_impl(
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
    raise exception 'authentication_required';
  end if;

  if new_latitude not between -90 and 90
     or new_longitude not between -180 and 180 then
    raise exception 'invalid_location';
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

create function public.update_my_location(
  new_latitude double precision,
  new_longitude double precision
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.update_my_location_impl(new_latitude, new_longitude);
end;
$$;

create function public.update_my_location_with_result(
  new_latitude double precision,
  new_longitude double precision
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.update_my_location_impl(new_latitude, new_longitude);
$$;

revoke all on function private.update_my_location_impl(
  double precision,
  double precision
) from public, anon;
revoke all on function public.update_my_location(
  double precision,
  double precision
) from public, anon;
revoke all on function public.update_my_location_with_result(
  double precision,
  double precision
) from public, anon;

grant execute on function private.update_my_location_impl(
  double precision,
  double precision
) to authenticated, service_role;
grant execute on function public.update_my_location(
  double precision,
  double precision
) to authenticated, service_role;
grant execute on function public.update_my_location_with_result(
  double precision,
  double precision
) to authenticated, service_role;

comment on function private.update_my_location_impl(
  double precision,
  double precision
) is 'Returns true only when the tracked location was written; enforces the 60-second, 100-metre, and 12-hour limits.';

notify pgrst, 'reload schema';
