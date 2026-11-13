begin;

insert into auth.users (id, is_sso_user, is_anonymous)
values
  ('10000000-0000-0000-0000-0000000000e1', false, false),
  ('10000000-0000-0000-0000-0000000000e2', false, false);

insert into public.user_locations (user_id, latitude, longitude, updated_at)
values
  ('10000000-0000-0000-0000-0000000000e1', 55.7558, 37.6173, now()),
  ('10000000-0000-0000-0000-0000000000e2', 59.9343, 30.3351, now());

insert into public.friendships (user_one_id, user_two_id)
values (
  '10000000-0000-0000-0000-0000000000e1',
  '10000000-0000-0000-0000-0000000000e2'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000e1', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  attempt integer;
begin
  for attempt in 1..30 loop
    perform public.get_friend_location_visibility(
      '10000000-0000-0000-0000-0000000000e2'
    );
  end loop;

  begin
    perform public.get_friend_location_visibility(
      '10000000-0000-0000-0000-0000000000e2'
    );
    raise exception 'Precise-location quota did not reject request 31';
  exception when sqlstate '42901' then
    if sqlerrm <> 'location_distance_rate_limited' then raise; end if;
  end;
end;
$$;

reset role;

do $$
declare
  counter integer;
begin
  select request_count into counter
  from private.location_distance_read_limits
  where viewer_user_id = '10000000-0000-0000-0000-0000000000e1'
    and target_user_id = '10000000-0000-0000-0000-0000000000e2';
  if counter <> 30 then
    raise exception 'Location quota kept writing after rejection: %', counter;
  end if;
end;
$$;

rollback;
