begin;

insert into auth.users (id, is_sso_user, is_anonymous)
values ('10000000-0000-0000-0000-000000000099', false, false);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000099',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000099","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  attempt integer;
  was_rate_limited boolean := false;
begin
  -- Mix all public write wrappers: they must consume one shared quota.
  perform public.update_my_location(55.0, 37.0);
  perform public.update_my_location_with_result(55.0, 37.0);
  for attempt in 3..10 loop
    perform public.update_my_location_with_metadata(55.0, 37.0);
  end loop;

  begin
    perform public.update_my_location_with_metadata(55.0, 37.0);
  exception
    when sqlstate '42901' then was_rate_limited := true;
  end;

  if not was_rate_limited then
    raise exception 'Location update attempt quota did not reject the eleventh request';
  end if;
end;
$$;

reset role;

do $$
declare
  attempt_count integer;
begin
  select request_count
  into attempt_count
  from private.location_update_attempt_limits
  where user_id = '10000000-0000-0000-0000-000000000099';

  if attempt_count <> 10 then
    raise exception 'Expected ten accepted location attempts, got %', attempt_count;
  end if;
end;
$$;

-- The next request starts a fresh window once the full minute has elapsed.
update private.location_update_attempt_limits
set window_started_at = statement_timestamp() - interval '1 minute'
where user_id = '10000000-0000-0000-0000-000000000099';

set local role authenticated;
select public.update_my_location_with_result(55.0, 37.0);
reset role;

do $$
declare
  attempt_count integer;
begin
  select request_count
  into attempt_count
  from private.location_update_attempt_limits
  where user_id = '10000000-0000-0000-0000-000000000099';

  if attempt_count <> 1 then
    raise exception 'Expected a fresh one-minute window, got %', attempt_count;
  end if;
end;
$$;

rollback;
