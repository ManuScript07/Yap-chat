begin;

do $$
begin
  if (
    select routine.provolatile
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.proname = 'get_user_distance'
      and pg_get_function_identity_arguments(routine.oid) = 'target_user_id uuid'
  ) <> 'v' then
    raise exception 'get_user_distance must remain VOLATILE because it records quota usage';
  end if;
end;
$$;

insert into auth.users (id, is_sso_user, is_anonymous)
values
  ('10000000-0000-0000-0000-000000000091', false, false),
  ('10000000-0000-0000-0000-000000000092', false, false);

insert into public.user_locations (user_id, latitude, longitude, updated_at)
values
  ('10000000-0000-0000-0000-000000000091', 55.7558, 37.6173, now()),
  ('10000000-0000-0000-0000-000000000092', 59.9343, 30.3351, now());

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000091',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000091","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  result_value integer;
  result_unit text;
begin
  select distance_value, distance_unit
  into result_value, result_unit
  from public.get_user_distance('10000000-0000-0000-0000-000000000092');

  if result_value is null or result_unit <> 'kilometers' then
    raise exception 'Server distance was not returned after quota consumption';
  end if;

end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1
    from private.location_distance_read_limits
    where viewer_user_id = '10000000-0000-0000-0000-000000000091'
      and target_user_id = '10000000-0000-0000-0000-000000000092'
  ) then
    raise exception 'Distance read quota was not recorded';
  end if;
end;
$$;

rollback;
