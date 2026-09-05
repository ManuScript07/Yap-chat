-- A view is counted at most once in twenty minutes, but the former logic did
-- not limit how often a client could execute the full profile RPC. Keep a
-- compact per-viewer/per-target window for both profile read endpoints.
create table if not exists private.profile_read_limits (
  viewer_user_id uuid not null,
  target_user_id uuid not null,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0),
  primary key (viewer_user_id, target_user_id)
);

revoke all on table private.profile_read_limits from public, anon, authenticated;

create or replace function private.consume_profile_read_quota(
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

  insert into private.profile_read_limits as limits (
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
  on conflict on constraint profile_read_limits_pkey do update
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
     or limits.request_count < 20
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'profile_read_rate_limited';
  end if;
end;
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
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_profile_read_quota(target_user_id);

  if private.is_account_globally_banned(target_user_id) then
    return query
    select profile.id, ''::text, 'Заблокированный пользователь'::text, null::date,
      null::text, null::text, null::timestamptz,
      ''::text, ''::text, true, null::timestamptz,
      '[]'::jsonb, 'blocked'::text, null::uuid, 0::bigint,
      '[]'::jsonb, 0::bigint, null::timestamptz, false
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;

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
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed;
    return;
  end if;

  return query select * from private.get_viewed_profile_impl(
    target_user_id,
    should_register_view
  );
end;
$$;

create or replace function public.get_profile_view_count(target_user_id uuid)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_profile_read_quota(target_user_id);
  if private.is_account_globally_banned(target_user_id)
     or private.is_blocked_by_impl(target_user_id, auth.uid()) then
    return 0;
  end if;
  return private.get_profile_view_count_impl(target_user_id);
end;
$$;

revoke all on function private.consume_profile_read_quota(uuid)
  from public, anon, authenticated;
revoke all on function public.get_viewed_profile(uuid, boolean) from public, anon;
revoke all on function public.get_profile_view_count(uuid) from public, anon;

grant execute on function private.consume_profile_read_quota(uuid)
  to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean)
  to authenticated, service_role;
grant execute on function public.get_profile_view_count(uuid)
  to authenticated, service_role;
