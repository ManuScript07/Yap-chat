-- End-to-end database contract for the reversible account-deletion lifecycle.
-- It rolls back all fixture data, so it is safe to run against a disposable
-- local Supabase database after migrations have been applied.

begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('30000000-0000-0000-0000-000000000001', false, false, '{"name":"Viewer"}'::jsonb),
  ('30000000-0000-0000-0000-000000000002', false, false, '{"name":"Pending deletion"}'::jsonb),
  ('30000000-0000-0000-0000-000000000003', false, false, '{"name":"Final deletion"}'::jsonb);

update public.profiles
set onboarding_completed = true,
    username = case id
      when '30000000-0000-0000-0000-000000000001'::uuid then 'deletion_viewer'
      when '30000000-0000-0000-0000-000000000002'::uuid then 'deletion_pending'
      else 'deletion_final'
    end,
    display_name = case id
      when '30000000-0000-0000-0000-000000000001'::uuid then 'Viewer'
      when '30000000-0000-0000-0000-000000000002'::uuid then 'Pending deletion'
      else 'Final deletion'
    end,
    birth_date = date '2000-01-01',
    gender = 'unspecified',
    last_seen_at = statement_timestamp()
where id between '30000000-0000-0000-0000-000000000001'::uuid
           and '30000000-0000-0000-0000-000000000003'::uuid;

update public.profiles
set avatar_url = null,
    avatar_storage_path = '30000000-0000-0000-0000-000000000003/primary.jpg',
    avatar_updated_at = statement_timestamp()
where id = '30000000-0000-0000-0000-000000000003';

insert into public.profile_photos (
  profile_id, position, avatar_url, storage_path, updated_at
) values
  (
    '30000000-0000-0000-0000-000000000003',
    0,
    null,
    '30000000-0000-0000-0000-000000000003/primary.jpg',
    statement_timestamp()
  ),
  (
    '30000000-0000-0000-0000-000000000003',
    1,
    null,
    '30000000-0000-0000-0000-000000000003/secondary.jpg',
    statement_timestamp()
  );

insert into public.friendships (user_one_id, user_two_id)
values (
  '30000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000002'
);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select public.create_direct_conversation('30000000-0000-0000-0000-000000000002');
select public.create_direct_conversation('30000000-0000-0000-0000-000000000003');
reset role;

-- This is the exact SQL bridge used by the authenticated Edge Function.
-- The trigger must make the account unusable immediately.
set local role service_role;
select * from public.request_account_deletion_from_service(
  '30000000-0000-0000-0000-000000000002',
  'self',
  'lifecycle test'
);
reset role;

do $$
begin
  if not private.is_account_pending_deletion(
    '30000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Pending-deletion account was not marked restricted';
  end if;
  if private.is_account_pending_deletion(
    '30000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'Deletion state leaked to an unrelated account';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = '30000000-0000-0000-0000-000000000002'
      and profile.account_deletion_requested_at is not null
  ) then
    raise exception 'Administrator insert did not mark the profile';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  chat_id uuid;
  viewed_name text;
  viewed_username text;
  summary_name text;
  summary_avatar text;
  summary_is_deleted boolean;
  friend_count integer;
  search_count integer;
begin
  select display_name, username into viewed_name, viewed_username
  from public.get_viewed_profile('30000000-0000-0000-0000-000000000002', false);
  if viewed_name <> 'Удалённый пользователь' or viewed_username <> '' then
    raise exception 'Pending-deletion profile was not redacted';
  end if;

  select id, peer_display_name, peer_avatar_url, peer_is_deleted
  into chat_id, summary_name, summary_avatar, summary_is_deleted
  from public.get_chat_summaries()
  where peer_id = '30000000-0000-0000-0000-000000000002';
  if chat_id is null or summary_name <> 'Удалённый пользователь'
     or summary_avatar is not null or summary_is_deleted is not true then
    raise exception 'Deleted chat summary is incorrect';
  end if;

  select count(*) into friend_count
  from public.get_friends_page(null, null, 50)
  where id = '30000000-0000-0000-0000-000000000002';
  if friend_count <> 0 then
    raise exception 'Pending-deletion account remained in own friends';
  end if;

  select count(*) into search_count
  from public.search_friend_candidates('@deletion_pending', 10)
  where id = '30000000-0000-0000-0000-000000000002';
  if search_count <> 0 then
    raise exception 'Pending-deletion account remained searchable';
  end if;

  begin
    perform public.send_chat_message(
      extensions.gen_random_uuid(), chat_id, 'text', 'must not be delivered'
    );
    raise exception 'Message to deletion-pending account was allowed';
  exception when sqlstate '42501' then
    if sqlerrm <> 'conversation_blocked' then raise; end if;
  end;

  begin
    perform public.send_friend_request('30000000-0000-0000-0000-000000000002');
    raise exception 'Friend request to deletion-pending account was allowed';
  exception when sqlstate '42501' then
    if sqlerrm <> 'friend_request_blocked' then raise; end if;
  end;
end;
$$;
reset role;

-- A restricted user cannot access the normal data API guard even with a
-- still-valid JWT; get_my_account_access is the sole recovery-screen exception.
select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;
do $$
declare
  access_banned boolean;
  access_pending boolean;
  access_expired boolean;
  access_scheduled_for timestamptz;
begin
  begin
    perform private.require_active_account();
    raise exception 'Pending-deletion account passed the active-account guard';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'account_pending_deletion' then raise; end if;
  end;
  select
    is_banned,
    is_deletion_pending,
    is_deletion_expired,
    deletion_scheduled_for
  into access_banned, access_pending, access_expired, access_scheduled_for
  from public.get_my_account_access();
  if access_banned or not access_pending or access_expired
     or access_scheduled_for is null
     or access_scheduled_for <= statement_timestamp() then
    raise exception 'Recovery access response is incorrect: %, %, %, %',
      access_banned, access_pending, access_expired, access_scheduled_for;
  end if;
end;
$$;
reset role;

-- Restore preserves conversations/friendships, removes the marker and makes
-- future sends possible. Deleted friend requests intentionally do not return.
set local role service_role;
select public.restore_account_deletion_from_service(
  '30000000-0000-0000-0000-000000000002'
);
reset role;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
do $$
declare chat_id uuid; friend_count integer;
begin
  select count(*) into friend_count
  from public.get_friends_page(null, null, 50)
  where id = '30000000-0000-0000-0000-000000000002';
  if friend_count <> 1 then
    raise exception 'Friendship was not restored';
  end if;
  select id into chat_id from public.get_chat_summaries()
  where peer_id = '30000000-0000-0000-0000-000000000002';
  perform public.send_chat_message(
    extensions.gen_random_uuid(), chat_id, 'text', 'delivery restored'
  );
end;
$$;
reset role;

-- The deadline is authoritative even before the hourly finalizer reaches the
-- account. The access response must therefore hide the restore action.
set local role service_role;
select * from public.request_account_deletion_from_service(
  '30000000-0000-0000-0000-000000000002', 'self', 'expiry test'
);
reset role;
update private.account_deletion_requests
set requested_at = statement_timestamp() - interval '31 days',
    scheduled_for = statement_timestamp() - interval '1 second'
where target_user_id = '30000000-0000-0000-0000-000000000002'
  and restored_at is null;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}', true
);
set local role authenticated;
do $$
declare
  access_pending boolean;
  access_expired boolean;
  access_scheduled_for timestamptz;
begin
  select is_deletion_pending, is_deletion_expired, deletion_scheduled_for
  into access_pending, access_expired, access_scheduled_for
  from public.get_my_account_access();
  if access_pending or not access_expired
     or access_scheduled_for is null
     or access_scheduled_for > statement_timestamp() then
    raise exception 'Expired deletion access response is incorrect: %, %, %',
      access_pending, access_expired, access_scheduled_for;
  end if;
end;
$$;
reset role;

set local role service_role;
do $$
declare attempt integer;
begin
  begin
    perform public.restore_account_deletion_from_service(
      '30000000-0000-0000-0000-000000000002'
    );
    raise exception 'Expired deletion was restorable';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'account_deletion_expired' then raise; end if;
  end;

  for attempt in 1..9 loop
    perform private.consume_account_deletion_action_quota(
      '30000000-0000-0000-0000-000000000002', 'restore'
    );
  end loop;
  begin
    perform private.consume_account_deletion_action_quota(
      '30000000-0000-0000-0000-000000000002', 'restore'
    );
    raise exception 'Account deletion action quota did not reject request 11';
  exception when sqlstate '42901' then
    if sqlerrm <> 'account_deletion_rate_limited' then raise; end if;
  end;
end;
$$;
reset role;

-- A short direct-admin window models a local test of the scheduled finalizer.
insert into private.account_deletion_requests (
  target_user_id, scheduled_for, requested_by, note
) values (
  '30000000-0000-0000-0000-000000000003',
  statement_timestamp(), 'admin', 'finalization test'
);

select private.finalize_due_account_deletions(10);

do $$
declare
  final_username text;
  final_name text;
  final_gender text;
  finalized_at timestamptz;
  user_banned_until timestamptz;
  user_metadata jsonb;
  queued_photo_count integer;
begin
  select profile.username, profile.display_name, profile.gender
  into final_username, final_name, final_gender
  from public.profiles profile
  where profile.id = '30000000-0000-0000-0000-000000000003';
  select request.finalized_at into finalized_at
  from private.account_deletion_requests request
  where request.target_user_id = '30000000-0000-0000-0000-000000000003';
  select banned_until, raw_user_meta_data into user_banned_until, user_metadata
  from auth.users where id = '30000000-0000-0000-0000-000000000003';

  if final_username !~ '^deleted_[a-z0-9]{16}$'
     or final_name <> 'Удалённый пользователь'
     or final_gender <> 'unspecified'
     or finalized_at is null
     or user_banned_until <> 'infinity'::timestamptz
     or user_metadata <> '{}'::jsonb then
    raise exception 'Final account tombstone is incomplete';
  end if;

  select count(*) into queued_photo_count
  from private.finalized_profile_media_cleanup_queue queue
  where queue.owner_user_id = '30000000-0000-0000-0000-000000000003'
    and queue.deleted_at is null;
  if queued_photo_count <> 2 then
    raise exception 'Finalized profile media was not queued: %', queued_photo_count;
  end if;

  begin
    update private.account_deletion_requests
    set restored_at = statement_timestamp()
    where target_user_id = '30000000-0000-0000-0000-000000000003';
    raise exception 'Finalized account was restorable';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'account_deletion_finalized' then raise; end if;
  end;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
do $$
declare chat_name text; chat_is_deleted boolean;
begin
  select peer_display_name, peer_is_deleted into chat_name, chat_is_deleted
  from public.get_chat_summaries()
  where peer_id = '30000000-0000-0000-0000-000000000003';
  if chat_name <> 'Удалённый пользователь' or chat_is_deleted is not true then
    raise exception 'Finalized account was not redacted in the chat';
  end if;
end;
$$;
reset role;

rollback;
