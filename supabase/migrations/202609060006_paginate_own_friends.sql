-- The own-friends screen is an unbounded list. Keep the old get_friends()
-- contract temporarily for installed clients, while new clients use this
-- cursor API and never receive the entire graph in one response.

create index if not exists friendships_user_one_created_peer_idx
  on public.friendships (user_one_id, created_at desc, user_two_id desc);

create index if not exists friendships_user_two_created_peer_idx
  on public.friendships (user_two_id, created_at desc, user_one_id desc);

create function private.get_friends_page_impl(
  after_friends_since timestamptz default null,
  after_friend_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz,
  has_more boolean,
  total_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_page_size integer := least(greatest(coalesce(page_size, 50), 1), 50);
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if (after_friends_since is null) <> (after_friend_id is null) then
    raise exception using errcode = '22023', message = 'invalid_friends_cursor';
  end if;

  return query
  -- Count independently. Materialising the complete union here would turn
  -- every subsequent page into an O(all friends) read and defeat the cursor.
  with total as materialized (
    select (
      (select count(*) from public.friendships friendship
       where friendship.user_one_id = current_user_id)
      +
      (select count(*) from public.friendships friendship
       where friendship.user_two_id = current_user_id)
    )::integer as value
  ), limited as materialized (
    select candidates.friend_id, candidates.friends_since
    from (
      select friendship.user_two_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_one_id = current_user_id
        and (
          after_friends_since is null
          or friendship.created_at < after_friends_since
          or (
            friendship.created_at = after_friends_since
            and friendship.user_two_id < after_friend_id
          )
        )

      union all

      select friendship.user_one_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_two_id = current_user_id
        and (
          after_friends_since is null
          or friendship.created_at < after_friends_since
          or (
            friendship.created_at = after_friends_since
            and friendship.user_one_id < after_friend_id
          )
        )
    ) candidates
    order by candidates.friends_since desc, candidates.friend_id desc
    limit normalized_page_size + 1
  ), page as materialized (
    select *
    from limited
    order by friends_since desc, friend_id desc
    limit normalized_page_size
  )
  select
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    page.friends_since,
    exists (select 1 from limited offset normalized_page_size),
    total.value
  from page
  join public.profiles peer on peer.id = page.friend_id
  cross join total
  order by page.friends_since desc, page.friend_id desc;
end;
$$;

create function public.get_friends_page(
  after_friends_since timestamptz default null,
  after_friend_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz,
  has_more boolean,
  total_count integer,
  is_online boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friends', 30);
  return query
  select
    friend.id,
    case when flags.globally_banned then '' else friend.username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else friend.display_name end,
    case when flags.globally_banned then null else friend.avatar_url end,
    case when flags.globally_banned then null else friend.avatar_storage_path end,
    friend.friends_since,
    friend.has_more,
    friend.total_count,
    not flags.globally_banned and private.is_user_online(friend.id)
  from private.get_friends_page_impl(
    after_friends_since,
    after_friend_id,
    page_size
  ) friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags;
end;
$$;

-- A profile identity change is broadcast to every friend. Refreshing the
-- first page would leave an already cached later page stale, while reloading
-- every page would undo pagination. Fetch just the affected cached friend.
create function private.get_current_friend_impl(target_friend_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if target_friend_id is null or target_friend_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_friend_target';
  end if;

  return query
  select
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    friendship.created_at
  from public.friendships friendship
  join public.profiles peer
    on peer.id = case
      when friendship.user_one_id = current_user_id then friendship.user_two_id
      else friendship.user_one_id
    end
  where target_friend_id = case
      when friendship.user_one_id = current_user_id then friendship.user_two_id
      else friendship.user_one_id
    end
    and current_user_id in (friendship.user_one_id, friendship.user_two_id)
  limit 1;
end;
$$;

create function public.get_current_friend(target_friend_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friends_since timestamptz,
  is_online boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.consume_network_read_quota('friends', 30);
  return query
  select
    friend.id,
    case when flags.globally_banned then '' else friend.username end,
    case when flags.globally_banned
      then 'Заблокированный пользователь' else friend.display_name end,
    case when flags.globally_banned then null else friend.avatar_url end,
    case when flags.globally_banned then null else friend.avatar_storage_path end,
    friend.friends_since,
    not flags.globally_banned and private.is_user_online(friend.id)
  from private.get_current_friend_impl(target_friend_id) friend
  cross join lateral (
    select private.is_account_globally_banned(friend.id) as globally_banned
  ) flags;
end;
$$;

revoke all on function private.get_friends_page_impl(timestamptz, uuid, integer)
  from public, anon;
revoke all on function public.get_friends_page(timestamptz, uuid, integer)
  from public, anon;
revoke all on function private.get_current_friend_impl(uuid)
  from public, anon;
revoke all on function public.get_current_friend(uuid)
  from public, anon;
grant execute on function private.get_friends_page_impl(timestamptz, uuid, integer)
  to authenticated, service_role;
grant execute on function public.get_friends_page(timestamptz, uuid, integer)
  to authenticated, service_role;
grant execute on function private.get_current_friend_impl(uuid)
  to authenticated, service_role;
grant execute on function public.get_current_friend(uuid)
  to authenticated, service_role;

comment on function public.get_friends_page(timestamptz, uuid, integer) is
  'Returns one stable cursor page of the current users own friends; max 50 rows.';

notify pgrst, 'reload schema';
