-- Local Supabase only. Fixture rows, function replacement and the isolated
-- sequence are rolled back; the application's sequence is never rewound.
begin;
set local statement_timeout = '60s';
create temporary sequence username_test_sequence start with 60000000000;

do $$
begin
  execute replace(
    pg_get_functiondef('private.generate_unique_username_impl()'::regprocedure),
    'public.username_sequence', 'pg_temp.username_test_sequence'
  );
end;
$$;

do $$
begin
  if private.generated_username_for_number(1) <> 'u0000001'
    or private.generated_username_for_number(35) <> 'u000000z'
    or private.generated_username_for_number(36) <> 'u0000010'
    or private.generated_username_for_number(78364164095) <> 'uzzzzzzz'
    or private.generated_username_for_number(0) is not null
    or private.generated_username_for_number(null) is not null
    or private.generated_username_for_number(78364164096) is not null
  then raise exception 'Base36 username format changed'; end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'private.generated_username_for_number(bigint)'::regprocedure
      and proconfig @> array['search_path=""']
      and not prosecdef
      and prosqlbody is not null
  ) then raise exception 'Private formatter search_path is not safely pinned'; end if;

  if has_function_privilege('anon', 'private.generate_unique_username_impl()', 'execute')
    or has_function_privilege('authenticated', 'private.generated_username_for_number(bigint)', 'execute')
    or has_function_privilege('anon', 'private.generated_username_for_number(bigint)', 'execute')
    or has_function_privilege('anon', 'public.get_or_create_my_profile(text,date,text)', 'execute')
    or (select prosecdef from pg_proc where oid = 'public.get_or_create_my_profile(text,date,text)'::regprocedure)
  then raise exception 'Username/own-profile privileges were broadened'; end if;
end;
$$;

-- Exercise the actual batch expression across every base36 digit boundary.
-- This separate table avoids changing application fixtures or their counter.
create temporary table username_format_profiles (username text not null);
create unique index username_format_lower_unique on username_format_profiles (lower(username));
create temporary sequence username_format_sequence;
do $$
declare definition text; occupied_number bigint; expected_number bigint;
  encoded text; remaining_number bigint;
begin
  definition := pg_get_functiondef('private.generate_unique_username_impl()'::regprocedure);
  definition := replace(definition, 'private.generate_unique_username_impl()', 'pg_temp.username_format_probe()');
  definition := replace(definition, 'pg_temp.username_test_sequence', 'pg_temp.username_format_sequence');
  definition := replace(definition, 'public.profiles', 'pg_temp.username_format_profiles');
  execute definition;

  foreach occupied_number in array array[
    1, 34, 35, 1295, 46655, 1679615, 60466175, 2176782335, 78364164094
  ]::bigint[] loop
    delete from pg_temp.username_format_profiles;
    insert into pg_temp.username_format_profiles values
      (private.generated_username_for_number(occupied_number));
    perform setval('pg_temp.username_format_sequence', occupied_number, false);
    expected_number := occupied_number + 1;
    -- Independent reference: the original variable-length base36 algorithm.
    remaining_number := expected_number;
    encoded := '';
    while remaining_number > 0 loop
      encoded := substr('0123456789abcdefghijklmnopqrstuvwxyz',
        (remaining_number % 36)::integer + 1, 1) || encoded;
      remaining_number := remaining_number / 36;
    end loop;
    encoded := 'u' || lpad(encoded, 7, '0');
    if pg_temp.username_format_probe() <> encoded
      or private.generated_username_for_number(expected_number) <> encoded
    then raise exception 'Batch/reference encoding differs at %', expected_number; end if;
  end loop;
end;
$$;

-- Real registration trigger: each free ticket must remain contiguous.
insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
select
  ('61000000-0000-0000-0000-' || lpad(to_hex(number), 12, '0'))::uuid,
  false, false,
  jsonb_build_object('name', 'Username fixture', 'birthdate', '2000-01-02')
from generate_series(1, 1000) number;

do $$
begin
  if exists (
    select 1 from generate_series(1, 1000) number
    join public.profiles profile
      on profile.id = ('61000000-0000-0000-0000-' || lpad(to_hex(number), 12, '0'))::uuid
    where profile.username <> private.generated_username_for_number(59999999999 + number)
      or profile.birth_date <> date '2000-01-02'
      or profile.display_name <> 'Username fixture'
      or profile.terms_accepted_at is not null
  ) then raise exception 'Registration metadata or free-ticket order changed'; end if;

  perform setval('pg_temp.username_test_sequence', 60000000000, false);
  if private.generate_unique_username_impl() <> private.generated_username_for_number(60000001000)
  then raise exception 'A chain of 1000 occupied names was not skipped'; end if;

  -- A small manual collision must not skip an earlier free hole in a batch.
  update public.profiles set username = 'username_manual_hole'
  where id = '61000000-0000-0000-0000-000000000002';
  perform setval('pg_temp.username_test_sequence', 60000000000, false);
  if private.generate_unique_username_impl() <> private.generated_username_for_number(60000000001)
  then raise exception 'Allocator skipped the first free hole'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true);
set local role authenticated;
-- An already-existing profile must not consume another sequence ticket.
select id from public.get_or_create_my_profile('Replacement name', date '2001-01-01', null);
select id from public.get_or_create_my_profile(null, null, null);
reset role;

do $$
begin
  if currval('pg_temp.username_test_sequence') <> 60000000128 then
    raise exception 'Existing profile bootstrap allocated a new username';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = '61000000-0000-0000-0000-000000000001'
      and username = private.generated_username_for_number(60000000000)
      and display_name = 'Username fixture' and birth_date = date '2000-01-02'
      and terms_accepted_at is not null and privacy_accepted_at is not null
  ) then raise exception 'Bootstrap overwrote profile or failed to retain consent'; end if;
end;
$$;

-- Existing Auth account with no profile exercises the invoker recovery path.
delete from public.profiles where id = '61000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select id from public.get_or_create_my_profile('Recovered', date '2000-01-03', null);
reset role;

do $$
declare conflict_name text;
begin
  if not exists (
    select 1 from public.profiles where id = '61000000-0000-0000-0000-000000000003'
      and username = private.generated_username_for_number(60000001000)
      and display_name = 'Recovered' and terms_accepted_at is not null
  ) then raise exception 'Missing-profile recovery failed'; end if;

  begin
    update public.profiles set username = private.generated_username_for_number(60000000000)
    where id = '61000000-0000-0000-0000-000000000003';
    raise exception 'Manual duplicate nickname was unexpectedly accepted';
  exception when unique_violation then
    get stacked diagnostics conflict_name = constraint_name;
    if conflict_name <> 'profiles_username_lower_unique' then raise; end if;
  end;

  -- Last valid name must remain usable, even if it lies in a partial batch.
  update public.profiles set username = private.generated_username_for_number(78364164094)
  where id = '61000000-0000-0000-0000-000000000001';
  perform setval('pg_temp.username_test_sequence', 78364164094, false);
  if private.generate_unique_username_impl() <> 'uzzzzzzz' then
    raise exception 'Last valid sequence ticket was skipped';
  end if;
  begin
    perform private.generate_unique_username_impl();
    raise exception 'Sequence exhaustion was unexpectedly ignored';
  exception when raise_exception then
    if sqlerrm <> 'Generated username sequence is exhausted' then raise; end if;
  end;
end;
$$;

-- Deterministically exercise retry ceilings and unrelated uniqueness errors.
-- The separate sequence counts attempts even when an INSERT subtransaction
-- rolls back; no hook or test routine survives the final ROLLBACK.
create temporary sequence username_retry_probe_sequence;
create function pg_temp.inject_username_probe_conflict()
returns trigger language plpgsql security definer set search_path = '' as $$
declare attempt_number bigint; failure_mode text;
begin
  if new.id::text is distinct from current_setting('username_probe.target_id', true)
  then return new; end if;
  attempt_number := nextval('pg_temp.username_retry_probe_sequence');
  failure_mode := current_setting('username_probe.failure_mode');
  if failure_mode = 'seven' and attempt_number = 8 then return new; end if;
  raise exception using
    errcode = '23505', message = 'Controlled username conflict',
    schema = 'public', table = 'profiles',
    constraint = case when failure_mode = 'unrelated'
      then 'unrelated_unique_constraint' else 'profiles_username_lower_unique' end;
end;
$$;
create trigger username_probe_conflict before insert on public.profiles
  for each row execute function pg_temp.inject_username_probe_conflict();

do $$
declare failure_mode text; target_id uuid; conflict_name text;
begin
  perform setval('pg_temp.username_test_sequence', 65000000000, false);
  foreach failure_mode in array array['seven', 'always', 'unrelated'] loop
    target_id := gen_random_uuid();
    perform set_config('username_probe.target_id', target_id::text, true);
    perform set_config('username_probe.failure_mode', failure_mode, true);
    perform setval('pg_temp.username_retry_probe_sequence', 1, false);
    begin
      insert into auth.users(id, is_sso_user, is_anonymous) values(target_id, false, false);
      if failure_mode <> 'seven' then raise exception 'Expected insertion failure'; end if;
    exception when unique_violation then
      get stacked diagnostics conflict_name = constraint_name;
      if failure_mode = 'seven' then raise; end if;
      if exists(select 1 from auth.users where id = target_id)
        or exists(select 1 from public.profiles where id = target_id)
      then raise exception 'Failed registration left partial account data'; end if;
      if failure_mode = 'unrelated' and conflict_name <> 'unrelated_unique_constraint'
      then raise exception 'Unrelated uniqueness exception was replaced'; end if;
    end;
    if currval('pg_temp.username_retry_probe_sequence') <> (case when failure_mode = 'unrelated' then 1 else 8 end)
    then raise exception 'Registration retry limit or constraint filtering failed'; end if;
  end loop;

  foreach failure_mode in array array['seven', 'always', 'unrelated'] loop
    target_id := gen_random_uuid();
    perform set_config('username_probe.target_id', '', true);
    insert into auth.users(id, is_sso_user, is_anonymous) values(target_id, false, false);
    delete from public.profiles where id = target_id;
    perform set_config('username_probe.target_id', target_id::text, true);
    perform set_config('username_probe.failure_mode', failure_mode, true);
    perform set_config('request.jwt.claim.sub', target_id::text, true);
    perform setval('pg_temp.username_retry_probe_sequence', 1, false);
    begin
      perform public.get_or_create_my_profile('Recovered', null, null);
      if failure_mode <> 'seven' then raise exception 'Expected bootstrap failure'; end if;
    exception when unique_violation then
      get stacked diagnostics conflict_name = constraint_name;
      if failure_mode = 'seven' then raise; end if;
      if exists(select 1 from public.profiles where id = target_id)
      then raise exception 'Failed bootstrap left partial profile data'; end if;
      if failure_mode = 'unrelated' and conflict_name <> 'unrelated_unique_constraint'
      then raise exception 'Bootstrap replaced unrelated uniqueness exception'; end if;
    end;
    if currval('pg_temp.username_retry_probe_sequence') <> (case when failure_mode = 'unrelated' then 1 else 8 end)
    then raise exception 'Bootstrap retry limit or constraint filtering failed'; end if;
  end loop;
end;
$$;
drop trigger username_probe_conflict on public.profiles;

-- Worst-case allocation work is bounded; the next request proceeds beyond
-- the occupied range rather than starting the same expensive scan again.
create temporary table username_bound_profiles(username text not null);
create unique index username_bound_lower_unique on username_bound_profiles(lower(username));
create temporary sequence username_bound_sequence;
insert into username_bound_profiles
select private.generated_username_for_number(number) from generate_series(1, 65537) number;
do $$
declare definition text;
begin
  definition := pg_get_functiondef('private.generate_unique_username_impl()'::regprocedure);
  definition := replace(definition, 'private.generate_unique_username_impl()', 'pg_temp.username_bound_generator()');
  definition := replace(definition, 'pg_temp.username_test_sequence', 'pg_temp.username_bound_sequence');
  definition := replace(definition, 'public.profiles', 'pg_temp.username_bound_profiles');
  execute definition;
  begin
    perform pg_temp.username_bound_generator();
    raise exception 'Allocation work limit was not enforced';
  exception when program_limit_exceeded then
    if sqlerrm <> 'username_allocation_busy' then raise; end if;
  end;
  if currval('pg_temp.username_bound_sequence') <> 65537 then
    raise exception 'Allocator did not respect its work bound';
  end if;
  if pg_temp.username_bound_generator() <> private.generated_username_for_number(65538) then
    raise exception 'A later request restarted the occupied range';
  end if;
end;
$$;

rollback;
