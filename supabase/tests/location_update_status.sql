begin;

insert into auth.users (id, is_sso_user, is_anonymous)
values ('10000000-0000-0000-0000-000000000098', false, false);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000098',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000098","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  first_write boolean;
  cooldown_write boolean;
  metadata record;
begin
  select public.update_my_location_with_result(55.0, 37.0) into first_write;
  select public.update_my_location_with_result(56.0, 38.0) into cooldown_write;

  if first_write is not true then
    raise exception 'Initial location update was not reported as written';
  end if;
  if cooldown_write is not false then
    raise exception 'Location cooldown was not reported to the client';
  end if;

  select * into metadata
  from public.update_my_location_with_metadata(56.0, 38.0);
  if metadata.did_update is not false
     or metadata.latitude <> 55.0
     or metadata.longitude <> 37.0
     or metadata.updated_at is null then
    raise exception 'Location metadata did not return the retained server point';
  end if;
end;
$$;

reset role;

do $$
declare
  stored_latitude double precision;
  stored_longitude double precision;
begin
  select latitude, longitude
  into stored_latitude, stored_longitude
  from public.user_locations
  where user_id = '10000000-0000-0000-0000-000000000098';

  if stored_latitude <> 55.0 or stored_longitude <> 37.0 then
    raise exception 'Cooldown-bypassed location changed on the server';
  end if;
end;
$$;

rollback;
