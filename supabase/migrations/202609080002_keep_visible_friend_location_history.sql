-- A friend who is still allowed to share their exact location may expose the
-- last known point even when it is older than one day. The client keeps a
-- separately marked, 24-hour frozen snapshot when sharing is later hidden.
create or replace function private.get_friend_location_visibility_impl(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz,
  availability text
)
language plpgsql stable security definer set search_path = ''
as $$
declare is_friend boolean; may_share_precise boolean; is_excluded boolean;
begin
  if auth.uid() is null or friend_user_id is null then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
    return;
  end if;

  select exists(
    select 1 from public.friendships friendship
    where friendship.user_one_id = least(auth.uid(), friend_user_id)
      and friendship.user_two_id = greatest(auth.uid(), friend_user_id)
  ) into is_friend;
  if not is_friend then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
    return;
  end if;

  select coalesce(settings.share_precise_location, true)
  into may_share_precise
  from public.profiles profile
  left join private.search_privacy_settings settings on settings.user_id = profile.id
  where profile.id = friend_user_id;

  select exists(
    select 1 from private.precise_location_exclusions exclusion
    where exclusion.owner_user_id = friend_user_id
      and exclusion.viewer_user_id = auth.uid()
  ) into is_excluded;
  if not coalesce(may_share_precise, true) or is_excluded then
    return query select null::double precision, null::double precision, null::timestamptz, 'hidden'::text;
    return;
  end if;

  return query
  select location.latitude, location.longitude, location.updated_at, 'current'::text
  from public.user_locations location
  where location.user_id = friend_user_id;
  if not found then
    return query select null::double precision, null::double precision, null::timestamptz, 'unavailable'::text;
  end if;
end;
$$;

revoke all on function private.get_friend_location_visibility_impl(uuid)
  from public, anon;
grant execute on function private.get_friend_location_visibility_impl(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
