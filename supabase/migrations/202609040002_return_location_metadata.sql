-- Retain the old boolean RPC for released clients. This companion returns the
-- existing server point even when the 60-second/100-metre guard skips a write,
-- allowing the local cache to enforce the same twelve-hour expiry offline.
create function private.update_my_location_with_metadata_impl(
  new_latitude double precision,
  new_longitude double precision
)
returns table (
  did_update boolean,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  did_update := private.update_my_location_impl(new_latitude, new_longitude);

  return query
  select
    did_update,
    location.latitude,
    location.longitude,
    location.updated_at
  from public.user_locations as location
  where location.user_id = auth.uid();
end;
$$;

create function public.update_my_location_with_metadata(
  new_latitude double precision,
  new_longitude double precision
)
returns table (
  did_update boolean,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from private.update_my_location_with_metadata_impl(
    new_latitude,
    new_longitude
  );
$$;

revoke all on function private.update_my_location_with_metadata_impl(
  double precision,
  double precision
) from public, anon;
revoke all on function public.update_my_location_with_metadata(
  double precision,
  double precision
) from public, anon;

grant execute on function private.update_my_location_with_metadata_impl(
  double precision,
  double precision
) to authenticated, service_role;
grant execute on function public.update_my_location_with_metadata(
  double precision,
  double precision
) to authenticated, service_role;

comment on function private.update_my_location_with_metadata_impl(
  double precision,
  double precision
) is 'Updates a tracked point when allowed and always returns its server timestamp and coordinates.';

notify pgrst, 'reload schema';
