-- Exact coordinates are at least as sensitive as a rounded distance. Reuse
-- the existing pair-scoped quota and stop writing ever-growing counters after
-- the limit is reached.
create or replace function private.consume_location_distance_read_quota(
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_count integer;
begin
  if current_user_id is null or target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.location_distance_read_limits as limits (
    viewer_user_id,
    target_user_id,
    window_started_at,
    request_count
  ) values (
    current_user_id,
    target_user_id,
    statement_timestamp(),
    1
  )
  on conflict on constraint location_distance_read_limits_pkey do update
  set
    window_started_at = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then statement_timestamp()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then 1
      else limits.request_count + 1
    end
  where limits.window_started_at <= statement_timestamp() - interval '1 minute'
     or limits.request_count < 30
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'location_distance_rate_limited';
  end if;
end;
$$;

create or replace function public.get_friend_location_visibility(friend_user_id uuid)
returns table (
  latitude double precision,
  longitude double precision,
  updated_at timestamptz,
  availability text
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null
     or friend_user_id is null
     or private.is_account_globally_banned(friend_user_id)
     or private.is_blocked_by_impl(friend_user_id, auth.uid()) then
    return;
  end if;

  perform private.consume_location_distance_read_quota(friend_user_id);
  return query
  select * from private.get_friend_location_visibility_impl(friend_user_id);
end;
$$;

revoke all on function private.consume_location_distance_read_quota(uuid)
  from public, anon;
revoke all on function public.get_friend_location_visibility(uuid) from public, anon;

grant execute on function private.consume_location_distance_read_quota(uuid)
  to authenticated, service_role;
grant execute on function public.get_friend_location_visibility(uuid)
  to authenticated, service_role;
