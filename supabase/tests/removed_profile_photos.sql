-- Transactional regression test: no fixture or Storage metadata survives.
begin;

insert into auth.users (id, is_sso_user, is_anonymous)
values ('70000000-0000-0000-0000-000000000001', false, false);

insert into storage.objects (bucket_id, name)
values
  ('avatars', '70000000-0000-0000-0000-000000000001/first.jpg'),
  ('avatars', '70000000-0000-0000-0000-000000000001/second.jpg'),
  ('avatars', '70000000-0000-0000-0000-000000000001/abandoned.jpg');

do $$
begin
  if (select count(*) from private.removed_profile_photo_cleanup_queue
      where owner_user_id = '70000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'New uploads were not queued with a grace period';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '70000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select public.save_own_profile('Photo test', date '2000-01-01',
  'unspecified', 'photo_test_700', '', jsonb_build_array(
    jsonb_build_object('storage_path',
      '70000000-0000-0000-0000-000000000001/first.jpg'),
    jsonb_build_object('storage_path',
      '70000000-0000-0000-0000-000000000001/second.jpg')
  ));

reset role;
do $$
begin
  if (select count(*) from private.removed_profile_photo_cleanup_queue
      where owner_user_id = '70000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Referenced uploads remained queued';
  end if;
end;
$$;

set local role authenticated;
do $$
begin
  if (select count(*) from storage.objects
      where bucket_id = 'avatars' and name like
        '70000000-0000-0000-0000-000000000001/%') <> 2 then
    raise exception 'Current photos are not readable or orphan is readable';
  end if;
end;
$$;

-- Direct table edits cannot enqueue a photo still referenced by the primary
-- profile column. The worker must never delete that live object.
delete from public.profile_photos
where profile_id = '70000000-0000-0000-0000-000000000001'
  and position = 0;
reset role;
do $$
begin
  if (select count(*) from private.removed_profile_photo_cleanup_queue
      where owner_user_id = '70000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Deleting a duplicate primary reference queued a live photo';
  end if;
end;
$$;
set local role authenticated;
insert into public.profile_photos (profile_id, position, storage_path)
values ('70000000-0000-0000-0000-000000000001', 0,
  '70000000-0000-0000-0000-000000000001/first.jpg');

select public.save_own_profile('Photo test', date '2000-01-01',
  'unspecified', 'photo_test_700', '', jsonb_build_array(
    jsonb_build_object('storage_path',
      '70000000-0000-0000-0000-000000000001/second.jpg'),
    jsonb_build_object('storage_path',
      '70000000-0000-0000-0000-000000000001/first.jpg')
  ));

reset role;
do $$
begin
  if (select count(*) from private.removed_profile_photo_cleanup_queue
      where owner_user_id = '70000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Reordering photos left a false cleanup task';
  end if;
end;
$$;

set local role authenticated;
select public.save_own_profile('Photo test', date '2000-01-01',
  'unspecified', 'photo_test_700', '', jsonb_build_array(
    jsonb_build_object('storage_path',
      '70000000-0000-0000-0000-000000000001/first.jpg')
  ));

do $$
begin
  if exists (select 1 from storage.objects
      where bucket_id = 'avatars' and name =
        '70000000-0000-0000-0000-000000000001/second.jpg') then
    raise exception 'Removed photo is still readable';
  end if;
  if not exists (select 1 from storage.objects
      where bucket_id = 'avatars' and name =
        '70000000-0000-0000-0000-000000000001/first.jpg') then
    raise exception 'Retained photo became unreadable';
  end if;
end;
$$;

reset role;
do $$
begin
  if not exists (select 1 from private.removed_profile_photo_cleanup_queue
      where storage_path =
        '70000000-0000-0000-0000-000000000001/second.jpg'
        and next_attempt_at <= statement_timestamp()) then
    raise exception 'Removed photo did not become due immediately';
  end if;
end;
$$;

set local role service_role;
do $$
declare
  claimed record;
begin
  select * into claimed
  from public.claim_removed_profile_photo_cleanup_batch(100)
  where storage_path =
    '70000000-0000-0000-0000-000000000001/second.jpg';
  if claimed.id is null then
    raise exception 'Removed photo was not claimable by the worker';
  end if;
  if exists (
    select 1 from public.claim_removed_profile_photo_cleanup_batch(100)
    where storage_path =
      '70000000-0000-0000-0000-000000000001/abandoned.jpg'
  ) then
    raise exception 'Abandoned upload was claimed before grace period';
  end if;
end;
$$;

set local role authenticated;
do $$
begin
  begin
    perform public.claim_removed_profile_photo_cleanup_batch(1);
    raise exception 'Authenticated user could claim the cleanup queue';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_own_profile('Photo test', date '2000-01-01',
      'unspecified', 'photo_test_700', '', jsonb_build_array(
        jsonb_build_object('storage_path',
          '70000000-0000-0000-0000-000000000001/second.jpg')
      ));
    raise exception 'Leased photo was unexpectedly reused';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

select public.adopt_imported_profile_avatar(
  '70000000-0000-0000-0000-000000000001/abandoned.jpg',
  statement_timestamp()
);
do $$
begin
  if exists (select 1 from storage.objects where name =
    '70000000-0000-0000-0000-000000000001/first.jpg') then
    raise exception 'Replacing an imported avatar left the old path readable';
  end if;
  if not exists (select 1 from storage.objects where name =
    '70000000-0000-0000-0000-000000000001/abandoned.jpg') then
    raise exception 'Imported avatar path was not readable';
  end if;
end;
$$;

reset role;
do $$
begin
  if not exists (select 1 from private.removed_profile_photo_cleanup_queue
    where storage_path =
      '70000000-0000-0000-0000-000000000001/first.jpg') then
    raise exception 'Replaced imported avatar was not queued';
  end if;
  if exists (select 1 from private.removed_profile_photo_cleanup_queue
    where storage_path =
      '70000000-0000-0000-0000-000000000001/abandoned.jpg') then
    raise exception 'Imported avatar remained queued';
  end if;
end;
$$;

rollback;
