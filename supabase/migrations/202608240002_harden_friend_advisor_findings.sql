-- Keep friend data accessible only through the audited RPC implementations.
-- Explicit policies document that direct authenticated table access is denied
-- and satisfy the RLS advisor without widening table privileges.
create policy "Friendships are RPC only"
on public.friendships
for all to authenticated
using (false)
with check (false);

create policy "Friend requests are RPC only"
on public.friend_requests
for all to authenticated
using (false)
with check (false);

create policy "User locations are RPC only"
on public.user_locations
for all to authenticated
using (false)
with check (false);

-- SECURITY DEFINER implementations do not belong in the exposed API schema.
-- Move them to private and retain public SECURITY INVOKER wrappers so the
-- mobile client contract remains unchanged.
alter function public.get_friends() set schema private;
alter function private.get_friends() rename to get_friends_impl;

alter function public.get_friend_requests() set schema private;
alter function private.get_friend_requests() rename to get_friend_requests_impl;

alter function public.search_friend_candidates(text, integer) set schema private;
alter function private.search_friend_candidates(text, integer)
  rename to search_friend_candidates_impl;

alter function public.send_friend_request(uuid) set schema private;
alter function private.send_friend_request(uuid) rename to send_friend_request_impl;

alter function public.cancel_friend_request(uuid) set schema private;
alter function private.cancel_friend_request(uuid) rename to cancel_friend_request_impl;

alter function public.respond_friend_request(uuid, boolean) set schema private;
alter function private.respond_friend_request(uuid, boolean)
  rename to respond_friend_request_impl;

alter function public.set_friends_count_visibility(boolean) set schema private;
alter function private.set_friends_count_visibility(boolean)
  rename to set_friends_count_visibility_impl;

alter function public.update_my_location(double precision, double precision)
  set schema private;
alter function private.update_my_location(double precision, double precision)
  rename to update_my_location_impl;

alter function public.get_friend_location(uuid) set schema private;
alter function private.get_friend_location(uuid) rename to get_friend_location_impl;

revoke all on function private.get_friends_impl() from public, anon;
revoke all on function private.get_friend_requests_impl() from public, anon;
revoke all on function private.search_friend_candidates_impl(text, integer)
from public, anon;
revoke all on function private.send_friend_request_impl(uuid) from public, anon;
revoke all on function private.cancel_friend_request_impl(uuid) from public, anon;
revoke all on function private.respond_friend_request_impl(uuid, boolean)
from public, anon;
revoke all on function private.set_friends_count_visibility_impl(boolean)
from public, anon;
revoke all on function private.update_my_location_impl(
  double precision,
  double precision
) from public, anon;
revoke all on function private.get_friend_location_impl(uuid) from public, anon;

grant execute on function private.get_friends_impl()
to authenticated, service_role;
grant execute on function private.get_friend_requests_impl()
to authenticated, service_role;
grant execute on function private.search_friend_candidates_impl(text, integer)
to authenticated, service_role;
grant execute on function private.send_friend_request_impl(uuid)
to authenticated, service_role;
grant execute on function private.cancel_friend_request_impl(uuid)
to authenticated, service_role;
grant execute on function private.respond_friend_request_impl(uuid, boolean)
to authenticated, service_role;
grant execute on function private.set_friends_count_visibility_impl(boolean)
to authenticated, service_role;
grant execute on function private.update_my_location_impl(
  double precision,
  double precision
) to authenticated, service_role;
grant execute on function private.get_friend_location_impl(uuid)
to authenticated, service_role;

create function public.get_friends()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_friends_impl();
$$;

create function public.get_friend_requests()
returns table (
  request_id uuid,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  peer_avatar_storage_path text,
  peer_friend_count bigint,
  direction text,
  requested_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_friend_requests_impl();
$$;

create function public.search_friend_candidates(
  search_query text,
  result_limit integer default 50
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from private.search_friend_candidates_impl(search_query, result_limit);
$$;

create function public.send_friend_request(peer_user_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.send_friend_request_impl(peer_user_id);
$$;

create function public.cancel_friend_request(target_request_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.cancel_friend_request_impl(target_request_id);
$$;

create function public.respond_friend_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.respond_friend_request_impl(target_request_id, accept_request);
$$;

create function public.set_friends_count_visibility(is_visible boolean)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_friends_count_visibility_impl(is_visible);
$$;

create function public.update_my_location(
  new_latitude double precision,
  new_longitude double precision
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.update_my_location_impl(new_latitude, new_longitude);
$$;

create function public.get_friend_location(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_friend_location_impl(friend_user_id);
$$;

revoke all on function public.get_friends() from public, anon;
revoke all on function public.get_friend_requests() from public, anon;
revoke all on function public.search_friend_candidates(text, integer)
from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.cancel_friend_request(uuid) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean)
from public, anon;
revoke all on function public.set_friends_count_visibility(boolean)
from public, anon;
revoke all on function public.update_my_location(
  double precision,
  double precision
) from public, anon;
revoke all on function public.get_friend_location(uuid) from public, anon;

grant execute on function public.get_friends()
to authenticated, service_role;
grant execute on function public.get_friend_requests()
to authenticated, service_role;
grant execute on function public.search_friend_candidates(text, integer)
to authenticated, service_role;
grant execute on function public.send_friend_request(uuid)
to authenticated, service_role;
grant execute on function public.cancel_friend_request(uuid)
to authenticated, service_role;
grant execute on function public.respond_friend_request(uuid, boolean)
to authenticated, service_role;
grant execute on function public.set_friends_count_visibility(boolean)
to authenticated, service_role;
grant execute on function public.update_my_location(
  double precision,
  double precision
) to authenticated, service_role;
grant execute on function public.get_friend_location(uuid)
to authenticated, service_role;
