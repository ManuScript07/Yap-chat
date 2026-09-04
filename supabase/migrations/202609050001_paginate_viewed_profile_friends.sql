-- A profile can have an unbounded number of friends.  Return bounded pages,
-- calculate mutual friends for only the returned rows and protect the RPC
-- from being used as a high-frequency graph-discovery endpoint.
create table if not exists private.profile_friend_list_read_limits (
  viewer_user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0),
  primary key (viewer_user_id, target_user_id)
);

revoke all on table private.profile_friend_list_read_limits
  from public, anon, authenticated;

create or replace function private.consume_profile_friend_list_read_quota(
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

  insert into private.profile_friend_list_read_limits as limits (
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
  on conflict on constraint profile_friend_list_read_limits_pkey do update
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
     or limits.request_count < 12
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'profile_friends_rate_limited';
  end if;
end;
$$;

-- Replace the former unbounded one-argument variants.  PostgreSQL function
-- identity includes every argument type, so CREATE OR REPLACE alone would
-- leave the old RPC overload exposed to installed clients.
drop function if exists public.get_user_profile_friends(uuid);
drop function if exists private.get_user_profile_friends_impl(uuid);

create function private.get_user_profile_friends_impl(
  target_user_id uuid,
  after_display_name text default null,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  mutual_friend_count integer,
  has_more boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_page_size integer := least(greatest(coalesce(page_size, 30), 1), 30);
begin
  if auth.uid() is null or target_user_id is null then
    return;
  end if;

  -- Preserve the former RPC behaviour for a profile that disappeared between
  -- navigation and the request: an empty list, not a foreign-key error from
  -- the quota row.
  if not exists (
    select 1 from public.profiles profile where profile.id = target_user_id
  ) then
    return;
  end if;

  if (after_display_name is null) <> (after_user_id is null) then
    raise exception using errcode = '22023', message = 'invalid_profile_friends_cursor';
  end if;

  perform private.consume_profile_friend_list_read_quota(target_user_id);

  return query
  with viewer_friends as materialized (
    select case
      when friendship.user_one_id = auth.uid() then friendship.user_two_id
      else friendship.user_one_id
    end as friend_id
    from public.friendships friendship
    where friendship.user_one_id = auth.uid()
       or friendship.user_two_id = auth.uid()
  ), limited as materialized (
    select
      peer.id,
      peer.username,
      peer.display_name,
      peer.avatar_url,
      peer.avatar_storage_path
    from public.friendships friendship
    join public.profiles peer
      on peer.id = case
        when friendship.user_one_id = target_user_id then friendship.user_two_id
        else friendship.user_one_id
      end
    where (friendship.user_one_id = target_user_id
        or friendship.user_two_id = target_user_id)
      and peer.id <> auth.uid()
      and peer.onboarding_completed
      and (
        after_display_name is null
        or peer.display_name > after_display_name
        or (peer.display_name = after_display_name and peer.id > after_user_id)
      )
    order by peer.display_name, peer.id
    limit normalized_page_size + 1
  ), page as materialized (
    select *
    from limited
    order by display_name, id
    limit normalized_page_size
  )
  select
    page.id,
    page.username,
    page.display_name,
    page.avatar_url,
    page.avatar_storage_path,
    coalesce(mutual.count, 0)::integer as mutual_friend_count,
    exists (select 1 from limited offset normalized_page_size) as has_more
  from page
  left join lateral (
    select count(*)::integer as count
    from public.friendships friendship
    join viewer_friends viewer_friend
      on viewer_friend.friend_id = case
        when friendship.user_one_id = page.id then friendship.user_two_id
        else friendship.user_one_id
      end
    where friendship.user_one_id = page.id
       or friendship.user_two_id = page.id
  ) mutual on true
  order by page.display_name, page.id;
end;
$$;

create function public.get_user_profile_friends(
  target_user_id uuid,
  after_display_name text default null,
  after_user_id uuid default null,
  page_size integer default 30
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  mutual_friend_count integer,
  has_more boolean
)
language sql
security invoker
set search_path = ''
as $$
  select
    friend.id,
    case when flags.globally_banned then '' else friend.username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else friend.display_name end,
    case when flags.globally_banned then null else friend.avatar_url end,
    case when flags.globally_banned then null else friend.avatar_storage_path end,
    case when flags.globally_banned then 0 else friend.mutual_friend_count end,
    friend.has_more
  from private.get_user_profile_friends_impl(
    target_user_id,
    after_display_name,
    after_user_id,
    page_size
  ) friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

revoke all on function private.consume_profile_friend_list_read_quota(uuid)
  from public, anon, authenticated;
revoke all on function private.get_user_profile_friends_impl(uuid, text, uuid, integer)
  from public, anon;
revoke all on function public.get_user_profile_friends(uuid, text, uuid, integer)
  from public, anon;
grant execute on function private.get_user_profile_friends_impl(uuid, text, uuid, integer)
  to authenticated, service_role;
grant execute on function public.get_user_profile_friends(uuid, text, uuid, integer)
  to authenticated, service_role;

comment on function public.get_user_profile_friends(uuid, text, uuid, integer) is
  'Returns up to 30 profile friends after a stable name/id cursor, with mutual-friend counts.';

notify pgrst, 'reload schema';
