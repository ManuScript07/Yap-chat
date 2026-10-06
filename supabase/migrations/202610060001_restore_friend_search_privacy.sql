-- Keep paginated friends discoverable even when outside downloaded pages,
-- but honour the target's discovery setting for every non-friend. Requests
-- alone are not friendship. Shared profile links have a separate resolver.
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
  left join private.search_privacy_settings privacy
    on privacy.user_id = profile.id
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, auth.uid())
   and request.pair_user_two_id = greatest(profile.id, auth.uid())
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where auth.uid() is not null
    and (
      friendship.id is not null
      or case
        when prepared.is_username_search then coalesce(privacy.search_by_username, true)
        else coalesce(privacy.search_by_name, true)
      end
    )
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

-- CREATE OR REPLACE preserves existing ACLs. Do not widen access or change the
-- public wrapper's block, global-ban and account-deletion filters.

-- This legacy, unused discovery view enumerates profiles without search flags.
-- Keep it available for administrative maintenance, not for API clients. The
-- application uses the scoped search/profile RPCs, including the link resolver.
revoke all on public.public_profiles from public, anon, authenticated;
revoke all on function private.get_public_profiles_impl()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
