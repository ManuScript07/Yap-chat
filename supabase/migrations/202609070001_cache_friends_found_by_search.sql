-- Cursor pagination means an existing friend can be outside the currently
-- downloaded pages. Search must still identify that relationship, while the
-- client can cache just that friend instead of downloading every page.

create or replace function private.search_friend_candidates_impl(
  search_query text,
  result_limit integer default 10
)
returns table (
  id uuid,
  request_id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security definer
set search_path = ''
as $$
  with normalized as (
    select lower(btrim(coalesce(search_query, ''))) as query
  ),
  prepared as (
    select
      normalized.query,
      left(normalized.query, 1) = '@' as is_username_search,
      case
        when left(normalized.query, 1) = '@'
          then substr(normalized.query, 2)
        else normalized.query
      end as search_value
    from normalized
  )
  select
    profile.id,
    request.id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when profile.show_friends_count or profile.id = auth.uid()
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    case
      when friendship.id is not null then 'friend'
      when request.sender_id = auth.uid() then 'outgoing'
      when request.recipient_id = auth.uid() then 'incoming'
      else 'none'
    end
  from prepared
  join public.profiles profile
    on profile.id <> auth.uid()
   and profile.onboarding_completed
   and (
     (
       prepared.is_username_search
       and prepared.search_value ~ '^[a-z0-9_]{3,24}$'
       and lower(profile.username) = prepared.search_value
     )
     or (
       not prepared.is_username_search
       and char_length(prepared.search_value) >= 3
       and to_tsvector('simple'::regconfig, profile.display_name)
         @@ private.display_name_prefix_query(prepared.search_value)
     )
   )
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, auth.uid())
   and friendship.user_two_id = greatest(profile.id, auth.uid())
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, auth.uid())
   and request.pair_user_two_id = greatest(profile.id, auth.uid())
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where auth.uid() is not null
  order by
    prepared.is_username_search desc,
    (lower(profile.display_name) = prepared.search_value) desc,
    (left(lower(profile.display_name), length(prepared.search_value)) = prepared.search_value) desc,
    lower(profile.display_name),
    profile.id
  limit case
    when (select is_username_search from prepared) then 1
    else least(greatest(coalesce(result_limit, 10), 1), 10)
  end;
$$;

create function private.get_current_friends_impl(target_friend_ids uuid[])
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

  return query
  with requested as materialized (
    select distinct requested.id
    from unnest(coalesce(target_friend_ids, array[]::uuid[])) as requested(id)
    where requested.id is not null
      and requested.id <> current_user_id
    limit 500
  )
  select
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    friendship.created_at
  from requested
  join public.friendships friendship
    on friendship.user_one_id = least(requested.id, current_user_id)
   and friendship.user_two_id = greatest(requested.id, current_user_id)
  join public.profiles peer on peer.id = requested.id;
end;
$$;

create function public.get_current_friends(target_friend_ids uuid[])
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
    friend.username,
    friend.display_name,
    friend.avatar_url,
    friend.avatar_storage_path,
    friend.friends_since,
    private.is_user_online(friend.id)
  from private.get_current_friends_impl(target_friend_ids) friend
  where not private.is_account_globally_banned(friend.id)
    and not private.is_blocked_by_impl(friend.id, auth.uid());
end;
$$;

revoke all on function private.get_current_friends_impl(uuid[])
  from public, anon;
revoke all on function public.get_current_friends(uuid[])
  from public, anon;
grant execute on function private.get_current_friends_impl(uuid[])
  to authenticated, service_role;
grant execute on function public.get_current_friends(uuid[])
  to authenticated, service_role;

comment on function public.get_current_friends(uuid[]) is
  'Returns up to 500 verified current friends so search/contact hits can extend the local friend cache.';

notify pgrst, 'reload schema';
