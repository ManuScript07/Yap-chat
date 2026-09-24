-- Keep the avatar bucket private even after a photo is removed from a profile.
-- Physical deletion is asynchronous, but authorization changes in the same
-- transaction as the profile edit. Storage objects must be removed via the
-- Storage API, never by deleting rows from storage.objects.
create table private.removed_profile_photo_cleanup_queue (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_user_id uuid not null,
  bucket_id text not null default 'avatars' check (bucket_id = 'avatars'),
  storage_path text not null,
  queued_at timestamptz not null default statement_timestamp(),
  next_attempt_at timestamptz not null default statement_timestamp(),
  last_attempt_at timestamptz,
  lease_expires_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  deleted_at timestamptz,
  unique (bucket_id, storage_path),
  check (storage_path like owner_user_id::text || '/%')
);

create index removed_profile_photo_cleanup_due_idx
  on private.removed_profile_photo_cleanup_queue (next_attempt_at, queued_at, id)
  where deleted_at is null;

revoke all on private.removed_profile_photo_cleanup_queue from public, anon, authenticated;

-- Uploads that never reach save_own_profile must not survive an app crash or
-- uninstall. Give a legitimate in-progress edit one day to create a reference.
create function private.track_new_avatar_object()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  existing_queue private.removed_profile_photo_cleanup_queue%rowtype;
begin
  if new.bucket_id = 'avatars'
      and split_part(new.name, '/', 1) ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and not private.avatar_path_is_current_impl(new.name) then
    select * into existing_queue
    from private.removed_profile_photo_cleanup_queue queue
    where queue.bucket_id = 'avatars' and queue.storage_path = new.name
    for update;
    if found and existing_queue.lease_expires_at > statement_timestamp() then
      raise exception 'Removed profile photo is being deleted'
        using errcode = '22023';
    end if;
    insert into private.removed_profile_photo_cleanup_queue (
      owner_user_id, storage_path, next_attempt_at
    ) values (
      split_part(new.name, '/', 1)::uuid,
      new.name,
      statement_timestamp() + interval '24 hours'
    ) on conflict (bucket_id, storage_path) do update
    set deleted_at = null,
        queued_at = statement_timestamp(),
        next_attempt_at = statement_timestamp() + interval '24 hours',
        lease_expires_at = null,
        attempts = 0,
        last_error = null;
  end if;
  return new;
end;
$$;

create trigger track_new_avatar_object
after insert on storage.objects
for each row execute function private.track_new_avatar_object();

create function private.track_removed_profile_photo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  photo_owner uuid;
  photo_path text;
  existing_queue private.removed_profile_photo_cleanup_queue%rowtype;
begin
  if tg_table_name = 'profiles' then
    photo_owner := new.id;
    photo_path := new.avatar_storage_path;
  elsif tg_op = 'INSERT' or tg_op = 'UPDATE' then
    photo_owner := new.profile_id;
    photo_path := new.storage_path;
  else
    photo_owner := old.profile_id;
    photo_path := old.storage_path;
  end if;

  -- A previously removed path may only be restored before a worker claims
  -- it. This also prevents a stale client from reviving an already deleted file.
  if tg_op <> 'DELETE' and photo_path is not null then
    select * into existing_queue
    from private.removed_profile_photo_cleanup_queue queue
    where queue.bucket_id = 'avatars' and queue.storage_path = photo_path
    for update;
    if found then
      if existing_queue.deleted_at is not null
          or existing_queue.lease_expires_at > statement_timestamp() then
        raise exception 'Removed profile photo cannot be reused'
          using errcode = '22023';
      end if;
      delete from private.removed_profile_photo_cleanup_queue queue
      where queue.id = existing_queue.id;
    end if;
  end if;

  if tg_table_name = 'profiles' then
    if old.avatar_storage_path is distinct from new.avatar_storage_path then
      photo_path := old.avatar_storage_path;
    else
      photo_path := null;
    end if;
  elsif tg_op = 'DELETE' then
    photo_path := old.storage_path;
  elsif tg_op = 'UPDATE'
      and old.storage_path is distinct from new.storage_path then
    photo_path := old.storage_path;
  else
    photo_path := null;
  end if;

  if photo_path is not null
      and photo_path like photo_owner::text || '/%'
      and not private.avatar_path_is_current_impl(photo_path)
      and not exists (
        select 1 from private.account_deletion_requests request
        where request.target_user_id = photo_owner
          and request.restored_at is null and request.finalized_at is null
      ) then
    insert into private.removed_profile_photo_cleanup_queue (
      owner_user_id, storage_path
    ) values (photo_owner, photo_path)
    on conflict (bucket_id, storage_path) do nothing;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger track_removed_profile_photo_rows
after insert or delete on public.profile_photos
for each row execute function private.track_removed_profile_photo();

create trigger track_replaced_profile_photo_rows
after update of storage_path on public.profile_photos
for each row execute function private.track_removed_profile_photo();

create trigger track_removed_primary_profile_photo
after update of avatar_storage_path on public.profiles
for each row execute function private.track_removed_profile_photo();

-- This check covers both queued removals and historical orphaned objects.
-- The owner lookup is by primary key; photo positions are capped at five.
create function private.avatar_path_is_current_impl(candidate_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when split_part(candidate_path, '/', 1) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (
      select 1 from public.profiles profile
      where profile.id = split_part(candidate_path, '/', 1)::uuid
        and profile.avatar_storage_path = candidate_path
    ) or exists (
      select 1 from public.profile_photos photo
      where photo.profile_id = split_part(candidate_path, '/', 1)::uuid
        and photo.storage_path = candidate_path
    )
    else false
  end;
$$;

-- One-time cleanup of historical orphans. Recent objects keep the same
-- 24-hour grace period as uploads made after this migration.
insert into private.removed_profile_photo_cleanup_queue (
  owner_user_id, storage_path, next_attempt_at
)
select split_part(object.name, '/', 1)::uuid, object.name,
  greatest(object.created_at + interval '24 hours', statement_timestamp())
from storage.objects object
where object.bucket_id = 'avatars'
  and split_part(object.name, '/', 1) ~*
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and not private.avatar_path_is_current_impl(object.name)
on conflict (bucket_id, storage_path) do nothing;

drop policy if exists "Users can read non-blocked avatars" on storage.objects;
create policy "Users can read non-blocked avatars"
on storage.objects for select to authenticated
using (
  bucket_id = 'avatars'
  and private.avatar_path_is_current_impl(name)
  and not private.avatar_owner_blocks_current_viewer_impl((storage.foldername(name))[1])
  and not private.avatar_owner_is_pending_deletion_impl((storage.foldername(name))[1])
  and not private.avatar_owner_is_globally_banned((storage.foldername(name))[1])
);

create function private.claim_removed_profile_photo_cleanup_batch(
  requested_batch_size integer default 100
)
returns table (id uuid, owner_user_id uuid, bucket_id text, storage_path text)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
  with due as (
    select queue.id
    from private.removed_profile_photo_cleanup_queue queue
    where queue.deleted_at is null
      and queue.next_attempt_at <= statement_timestamp()
      and (queue.lease_expires_at is null or queue.lease_expires_at <= statement_timestamp())
    order by queue.next_attempt_at, queue.queued_at, queue.id
    limit least(greatest(coalesce(requested_batch_size, 100), 1), 100)
    for update skip locked
  ), claimed as (
    update private.removed_profile_photo_cleanup_queue queue
    set attempts = queue.attempts + 1,
        last_attempt_at = statement_timestamp(),
        lease_expires_at = statement_timestamp() + interval '10 minutes'
    from due where queue.id = due.id
    returning queue.id, queue.owner_user_id, queue.bucket_id, queue.storage_path
  )
  select claimed.id, claimed.owner_user_id, claimed.bucket_id, claimed.storage_path
  from claimed;
end;
$$;

create function private.complete_removed_profile_photo_cleanup(queue_ids uuid[])
returns void language sql security definer set search_path = ''
as $$
  update private.removed_profile_photo_cleanup_queue queue
  set deleted_at = statement_timestamp(), lease_expires_at = null,
      next_attempt_at = statement_timestamp(), last_error = null
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[])) and queue.deleted_at is null;
$$;

create function private.defer_removed_profile_photo_cleanup(
  queue_ids uuid[], failure_message text
)
returns void language sql security definer set search_path = ''
as $$
  update private.removed_profile_photo_cleanup_queue queue
  set lease_expires_at = null,
      next_attempt_at = statement_timestamp() + least(
        (2 ^ least(queue.attempts, 10)) * interval '1 minute', interval '24 hours'
      ),
      last_error = coalesce(nullif(left(btrim(failure_message), 500), ''), 'storage_cleanup_failed')
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[])) and queue.deleted_at is null;
$$;

create function public.claim_removed_profile_photo_cleanup_batch(requested_batch_size integer default 100)
returns table (id uuid, owner_user_id uuid, bucket_id text, storage_path text)
language sql security invoker set search_path = ''
as $$ select * from private.claim_removed_profile_photo_cleanup_batch(requested_batch_size); $$;

create function public.complete_removed_profile_photo_cleanup(queue_ids uuid[])
returns void language sql security invoker set search_path = ''
as $$ select private.complete_removed_profile_photo_cleanup(queue_ids); $$;

create function public.defer_removed_profile_photo_cleanup(queue_ids uuid[], failure_message text)
returns void language sql security invoker set search_path = ''
as $$ select private.defer_removed_profile_photo_cleanup(queue_ids, failure_message); $$;

revoke all on function private.track_new_avatar_object() from public, anon, authenticated;
revoke all on function private.track_removed_profile_photo() from public, anon, authenticated;
revoke all on function private.avatar_path_is_current_impl(text) from public, anon, authenticated;
revoke all on function private.claim_removed_profile_photo_cleanup_batch(integer) from public, anon, authenticated;
revoke all on function private.complete_removed_profile_photo_cleanup(uuid[]) from public, anon, authenticated;
revoke all on function private.defer_removed_profile_photo_cleanup(uuid[], text) from public, anon, authenticated;
revoke all on function public.claim_removed_profile_photo_cleanup_batch(integer) from public, anon, authenticated;
revoke all on function public.complete_removed_profile_photo_cleanup(uuid[]) from public, anon, authenticated;
revoke all on function public.defer_removed_profile_photo_cleanup(uuid[], text) from public, anon, authenticated;

grant execute on function private.avatar_path_is_current_impl(text) to authenticated;
grant execute on function private.claim_removed_profile_photo_cleanup_batch(integer) to service_role;
grant execute on function private.complete_removed_profile_photo_cleanup(uuid[]) to service_role;
grant execute on function private.defer_removed_profile_photo_cleanup(uuid[], text) to service_role;
grant execute on function public.claim_removed_profile_photo_cleanup_batch(integer) to service_role;
grant execute on function public.complete_removed_profile_photo_cleanup(uuid[]) to service_role;
grant execute on function public.defer_removed_profile_photo_cleanup(uuid[], text) to service_role;
