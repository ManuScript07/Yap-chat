-- Run only against a disposable local Supabase database. All fixtures roll back.
begin;

do $$
declare
  initial_user uuid := gen_random_uuid();
  edited_user uuid := gen_random_uuid();
  late_user uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (initial_user, initial_user::text || '@example.test',
      '{"name":"Birthday fixture","birthdate":"2007-02-28"}'::jsonb),
    (edited_user, edited_user::text || '@example.test',
      '{"name":"Edited fixture","birthdate":"2007-02-28"}'::jsonb),
    (late_user, late_user::text || '@example.test',
      '{"name":"Late fixture"}'::jsonb);

  if (select birth_date from public.profiles where id = initial_user)
      is distinct from date '2007-02-28' then
    raise exception 'Initial birthdate metadata was not imported';
  end if;

  update public.profiles set birth_date = date '2000-02-29'
  where id = edited_user;
  update auth.users
  set raw_user_meta_data = raw_user_meta_data || '{"birthdate":"2007-02-28"}'::jsonb
  where id = late_user;

  -- Store fixture ids in transaction-local settings for authenticated RPC calls.
  perform set_config('test.birthday_initial_user', initial_user::text, true);
  perform set_config('test.birthday_edited_user', edited_user::text, true);
  perform set_config('test.birthday_late_user', late_user::text, true);
end;
$$;

set local role authenticated;

do $$
declare
  profile record;
begin
  perform set_config('request.jwt.claim.sub', current_setting('test.birthday_initial_user'), true);
  select * into profile from public.get_or_create_my_profile(
    p_display_name => 'Birthday fixture', p_birth_date => date '2007-02-28'
  );
  if profile.birth_date is distinct from date '2007-02-28' then
    raise exception 'Profile bootstrap changed the imported date';
  end if;

  perform set_config('request.jwt.claim.sub', current_setting('test.birthday_edited_user'), true);
  select * into profile from public.get_or_create_my_profile(
    p_display_name => 'Edited fixture', p_birth_date => date '2007-02-28'
  );
  if profile.birth_date is distinct from date '2000-02-29' then
    raise exception 'Yandex date replaced the user-edited profile date';
  end if;

  perform set_config('request.jwt.claim.sub', current_setting('test.birthday_late_user'), true);
  select * into profile from public.get_or_create_my_profile(
    p_display_name => 'Late fixture', p_birth_date => date '2007-02-28'
  );
  if profile.birth_date is distinct from date '2007-02-28' then
    raise exception 'Client birthdate did not fill the empty profile date';
  end if;

  raise notice 'PASS: initial import, preserved user date, late date backfill';
end;
$$;

rollback;
