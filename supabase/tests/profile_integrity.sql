begin;

insert into auth.users (id, is_sso_user, is_anonymous)
values
  ('10000000-0000-0000-0000-000000000001', false, false),
  ('10000000-0000-0000-0000-000000000002', false, false);

update public.profiles
set username = 'already_taken'
where id = '10000000-0000-0000-0000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);
set local role authenticated;

do $$
declare
  target_user_id constant uuid :=
    '10000000-0000-0000-0000-000000000001';
  adopted_path constant text :=
    '10000000-0000-0000-0000-000000000001/imported.jpg';
  saved_username text;
  saved_storage_path text;
  saved_photo_count integer;
begin
  perform public.adopt_imported_profile_avatar(adopted_path, now());

  select profile.avatar_storage_path
  into saved_storage_path
  from public.profiles profile
  where profile.id = target_user_id;

  if saved_storage_path is distinct from adopted_path then
    raise exception 'Imported avatar was not adopted by the profile';
  end if;

  select photo.storage_path
  into saved_storage_path
  from public.profile_photos photo
  where photo.profile_id = target_user_id and photo.position = 0;

  if saved_storage_path is distinct from adopted_path then
    raise exception 'Imported avatar was not adopted by profile_photos';
  end if;

  perform public.save_own_profile(
    'Updated User',
    date '2000-01-01',
    'unspecified',
    '  Mixed_Case  ',
    'Bio',
    jsonb_build_array(
      jsonb_build_object('storage_path', adopted_path),
      jsonb_build_object(
        'storage_path',
        target_user_id::text || '/second.jpg'
      )
    )
  );

  select profile.username
  into saved_username
  from public.profiles profile
  where profile.id = target_user_id;

  if saved_username is distinct from 'mixed_case' then
    raise exception 'Username was not normalized: %', saved_username;
  end if;

  select count(*)
  into saved_photo_count
  from public.profile_photos photo
  where photo.profile_id = target_user_id;

  if saved_photo_count <> 2 then
    raise exception 'Expected two atomically saved photos, got %',
      saved_photo_count;
  end if;

  perform public.save_own_profile(
    'Updated User',
    date '2000-01-01',
    'unspecified',
    'mixed_case',
    'Bio',
    jsonb_build_array(
      jsonb_build_object(
        'storage_path',
        target_user_id::text || '/second.jpg'
      ),
      jsonb_build_object('storage_path', adopted_path)
    )
  );

  if (
    select array_agg(photo.storage_path order by photo.position)
    from public.profile_photos photo
    where photo.profile_id = target_user_id
  ) is distinct from array[
    target_user_id::text || '/second.jpg',
    adopted_path
  ] then
    raise exception 'Profile photo order was not persisted';
  end if;

  select profile.avatar_storage_path
  into saved_storage_path
  from public.profiles profile
  where profile.id = target_user_id;

  if saved_storage_path is distinct from
      target_user_id::text || '/second.jpg' then
    raise exception 'Primary profile photo does not match saved order';
  end if;

  perform public.save_own_profile(
    'Updated User',
    date '2000-01-01',
    'unspecified',
    'mixed_case',
    'Bio',
    '[]'::jsonb
  );

  if not (
    select profile.yandex_avatar_disabled
    from public.profiles profile
    where profile.id = target_user_id
  ) then
    raise exception 'Removing every photo did not disable Yandex avatar import';
  end if;

  begin
    perform public.save_own_profile(
      'Updated User',
      date '2000-01-01',
      'unspecified',
      'already_taken',
      'Bio',
      '[]'::jsonb
    );
    raise exception 'Duplicate username was unexpectedly accepted';
  exception
    when unique_violation then
      null;
  end;

  begin
    perform public.adopt_imported_profile_avatar(
      '10000000-0000-0000-0000-000000000002/not-owned.jpg',
      now()
    );
    raise exception 'Foreign avatar path was unexpectedly accepted';
  exception
    when invalid_parameter_value then
      null;
  end;
end;
$$;

rollback;
