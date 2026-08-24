alter table public.profiles
add column share_location boolean not null default true;

create or replace function private.get_friend_location_impl(
  friend_user_id uuid
)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select location.latitude, location.longitude, location.updated_at
  from public.user_locations location
  join public.profiles profile on profile.id = location.user_id
  where location.user_id = friend_user_id
    and profile.share_location
    and location.updated_at >= now() - interval '24 hours'
    and exists (
      select 1
      from public.friendships friendship
      where friendship.user_one_id = least(auth.uid(), friend_user_id)
        and friendship.user_two_id = greatest(auth.uid(), friend_user_id)
    );
$$;

create function private.set_location_visibility_impl(is_visible boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  update public.profiles
  set share_location = is_visible
  where id = auth.uid();
end;
$$;

revoke all on function private.set_location_visibility_impl(boolean)
from public, anon;
grant execute on function private.set_location_visibility_impl(boolean)
to authenticated, service_role;

create function public.set_location_visibility(is_visible boolean)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_location_visibility_impl(is_visible);
$$;

revoke all on function public.set_location_visibility(boolean)
from public, anon;
grant execute on function public.set_location_visibility(boolean)
to authenticated, service_role;

comment on column public.profiles.share_location is
  'Controls whether accepted friends can retrieve the latest non-stale location.';
comment on function public.set_location_visibility(boolean) is
  'Future UI hook for hiding or showing the retained latest location.';
