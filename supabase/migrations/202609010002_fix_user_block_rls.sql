-- The first block migration intentionally kept public wrappers as invoker
-- functions. Two wrappers also read profiles directly, but profiles are only
-- readable by their owner under RLS. That yielded an empty blacklist and an
-- empty viewed-profile response for the blocked viewer.

create or replace function public.get_blocked_users()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select profile.id, profile.username, profile.display_name,
    profile.avatar_url, profile.avatar_storage_path, block.created_at
  from public.user_blocks block
  join public.profiles profile on profile.id = block.blocked_user_id
  where block.blocker_user_id = auth.uid()
  order by block.created_at desc, profile.id;
$$;

create or replace function private.get_blocked_profile_identity_impl(
  target_user_id uuid
)
returns table (id uuid, display_name text)
language sql stable security definer set search_path = ''
as $$
  select profile.id, profile.display_name
  from public.profiles profile
  where profile.id = target_user_id
    and profile.onboarding_completed;
$$;

create or replace function public.get_viewed_profile(
  target_user_id uuid,
  should_register_view boolean default true
)
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  photos jsonb, relationship text, request_id uuid, friend_count bigint,
  friends_preview jsonb, profile_view_count bigint, last_seen_at timestamptz,
  shows_last_seen boolean
)
language plpgsql security invoker set search_path = ''
as $$
begin
  if private.is_blocked_by_impl(target_user_id, auth.uid()) then
    if coalesce(should_register_view, true) then
      perform private.record_profile_view_impl(target_user_id);
    else
      perform private.get_profile_view_count_impl(target_user_id);
    end if;
    return query
    select profile.id, ''::text, profile.display_name, null::date,
      null::text, null::text, null::timestamptz,
      ''::text, ''::text, true, null::timestamptz,
      '[]'::jsonb, 'blocked'::text, null::uuid, 0::bigint,
      '[]'::jsonb, 0::bigint, null::timestamptz, false
    from private.get_blocked_profile_identity_impl(target_user_id) profile;
    return;
  end if;
  return query select * from private.get_viewed_profile_impl(
    target_user_id,
    should_register_view
  );
end;
$$;

-- A policy subquery is evaluated with the viewer's RLS privileges. Use a
-- narrowly scoped definer helper so the avatar policy can see a block row
-- owned by another user without making the table itself readable.
create or replace function private.avatar_owner_blocks_current_viewer_impl(
  avatar_owner_folder text
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.user_blocks block
    where block.blocker_user_id::text = avatar_owner_folder
      and block.blocked_user_id = auth.uid()
  );
$$;

drop policy if exists "Users can read non-blocked avatars" on storage.objects;
create policy "Users can read non-blocked avatars"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and not private.avatar_owner_blocks_current_viewer_impl(
    (storage.foldername(name))[1]
  )
);

-- Keep the public entry point robust even if the user_blocks table policy is
-- tightened later. The explicit auth.uid() predicate prevents cross-account
-- deletion, and broadcasts remain cache invalidations only.
create or replace function public.unblock_user(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  delete from public.user_blocks
  where blocker_user_id = current_user_id and blocked_user_id = target_user_id;
  perform private.broadcast_block_change_impl(
    current_user_id,
    target_user_id,
    'unblocked'
  );
end;
$$;

revoke all on function private.get_blocked_profile_identity_impl(uuid)
  from public, anon, authenticated;
revoke all on function private.avatar_owner_blocks_current_viewer_impl(text)
  from public, anon, authenticated;
revoke all on function public.get_blocked_users() from public, anon;
revoke all on function public.get_viewed_profile(uuid, boolean) from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function private.get_blocked_profile_identity_impl(uuid)
  to authenticated, service_role;
grant execute on function private.avatar_owner_blocks_current_viewer_impl(text)
  to authenticated, service_role;
grant execute on function public.get_blocked_users() to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean)
  to authenticated, service_role;
grant execute on function public.unblock_user(uuid) to authenticated, service_role;
