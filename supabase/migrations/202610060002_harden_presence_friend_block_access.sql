-- Client block writes must pass through the existing locked, rate-limited
-- RPCs, which also remove friendships/requests and send privacy invalidations.
-- SELECT remains available under the existing owner RLS policy.
revoke insert, update, delete on public.user_blocks from anon, authenticated;

-- Defense in depth for old inconsistent rows or trusted administrative writes.
-- Filter before LIMIT/counting so pagination does not expose blocked identities
-- or produce false has_more / total_count values.
create or replace function private.get_friends_page_impl(
  after_friends_since timestamptz default null,
  after_friend_id uuid default null,
  page_size integer default 50
)
returns table (
  id uuid, username text, display_name text, avatar_url text,
  avatar_storage_path text, friends_since timestamptz, has_more boolean,
  total_count integer
)
language plpgsql security definer set search_path = ''
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
  with total as materialized (
    select count(*)::integer as value
    from public.friendships friendship
    join public.profiles peer on peer.id = case
      when friendship.user_one_id = current_user_id then friendship.user_two_id
      else friendship.user_one_id end
    where current_user_id in (friendship.user_one_id, friendship.user_two_id)
      and not private.is_account_pending_deletion(peer.id)
      and not private.is_user_pair_blocked_impl(current_user_id, peer.id)
  ), limited as materialized (
    select candidates.friend_id, candidates.friends_since
    from (
      select friendship.user_two_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_one_id = current_user_id
        and not private.is_account_pending_deletion(friendship.user_two_id)
        and not private.is_user_pair_blocked_impl(current_user_id, friendship.user_two_id)
        and (after_friends_since is null or friendship.created_at < after_friends_since
          or (friendship.created_at = after_friends_since and friendship.user_two_id < after_friend_id))
      union all
      select friendship.user_one_id as friend_id, friendship.created_at as friends_since
      from public.friendships friendship
      where friendship.user_two_id = current_user_id
        and not private.is_account_pending_deletion(friendship.user_one_id)
        and not private.is_user_pair_blocked_impl(current_user_id, friendship.user_one_id)
        and (after_friends_since is null or friendship.created_at < after_friends_since
          or (friendship.created_at = after_friends_since and friendship.user_one_id < after_friend_id))
    ) candidates
    order by candidates.friends_since desc, candidates.friend_id desc
    limit normalized_page_size + 1
  ), page as materialized (
    select * from limited order by friends_since desc, friend_id desc limit normalized_page_size
  )
  select peer.id, peer.username, peer.display_name, peer.avatar_url,
    peer.avatar_storage_path, page.friends_since,
    exists (select 1 from limited offset normalized_page_size), total.value
  from page join public.profiles peer on peer.id = page.friend_id
  cross join total
  order by page.friends_since desc, page.friend_id desc;
end;
$$;

notify pgrst, 'reload schema';
