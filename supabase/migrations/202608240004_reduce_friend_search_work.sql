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
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(search_query, '')));
  search_value text;
  prefix_query tsquery;
  limited_result_count integer := least(
    greatest(coalesce(result_limit, 10), 1),
    10
  );
begin
  if current_user_id is null or normalized_query = '' then
    return;
  end if;

  if left(normalized_query, 1) = '@' then
    search_value := substr(normalized_query, 2);
    if search_value !~ '^[a-z0-9_]{3,24}$' then
      return;
    end if;

    return query
    with candidate_profile as materialized (
      select
        profile.id,
        profile.username,
        profile.display_name,
        profile.avatar_url,
        profile.avatar_storage_path,
        profile.show_friends_count
      from public.profiles profile
      where profile.id <> current_user_id
        and profile.onboarding_completed
        and lower(profile.username) = search_value
        and not exists (
          select 1
          from public.friendships friendship
          where friendship.user_one_id = least(profile.id, current_user_id)
            and friendship.user_two_id = greatest(profile.id, current_user_id)
        )
      limit 1
    )
    select
      candidate.id,
      request.id,
      candidate.username,
      candidate.display_name,
      candidate.avatar_url,
      candidate.avatar_storage_path,
      case
        when candidate.show_friends_count
          then coalesce(profile_count.friends_count, 0)::bigint
        else null
      end,
      case
        when request.sender_id = current_user_id then 'outgoing'
        when request.recipient_id = current_user_id then 'incoming'
        else 'none'
      end
    from candidate_profile candidate
    left join public.friend_requests request
      on request.pair_user_one_id = least(candidate.id, current_user_id)
     and request.pair_user_two_id = greatest(candidate.id, current_user_id)
    left join private.profile_friend_counts profile_count
      on profile_count.user_id = candidate.id;
    return;
  end if;

  search_value := normalized_query;
  if char_length(search_value) < 3 then
    return;
  end if;

  prefix_query := private.display_name_prefix_query(search_value);
  if prefix_query is null then
    return;
  end if;

  return query
  with candidate_profiles as materialized (
    select
      profile.id,
      profile.username,
      profile.display_name,
      profile.avatar_url,
      profile.avatar_storage_path,
      profile.show_friends_count,
      lower(profile.display_name) = search_value as is_exact_name,
      left(lower(profile.display_name), length(search_value)) = search_value
        as starts_with_search,
      lower(profile.display_name) as normalized_display_name
    from public.profiles profile
    where profile.id <> current_user_id
      and profile.onboarding_completed
      and to_tsvector('simple'::regconfig, profile.display_name) @@ prefix_query
      and not exists (
        select 1
        from public.friendships friendship
        where friendship.user_one_id = least(profile.id, current_user_id)
          and friendship.user_two_id = greatest(profile.id, current_user_id)
      )
    order by
      is_exact_name desc,
      starts_with_search desc,
      normalized_display_name,
      profile.id
    limit limited_result_count
  )
  select
    candidate.id,
    request.id,
    candidate.username,
    candidate.display_name,
    candidate.avatar_url,
    candidate.avatar_storage_path,
    case
      when candidate.show_friends_count
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    case
      when request.sender_id = current_user_id then 'outgoing'
      when request.recipient_id = current_user_id then 'incoming'
      else 'none'
    end
  from candidate_profiles candidate
  left join public.friend_requests request
    on request.pair_user_one_id = least(candidate.id, current_user_id)
   and request.pair_user_two_id = greatest(candidate.id, current_user_id)
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = candidate.id
  order by
    candidate.is_exact_name desc,
    candidate.starts_with_search desc,
    candidate.normalized_display_name,
    candidate.id;
end;
$$;

revoke all on function private.search_friend_candidates_impl(text, integer)
from public, anon;
grant execute on function private.search_friend_candidates_impl(text, integer)
to authenticated, service_role;

comment on function private.search_friend_candidates_impl(text, integer) is
  'Uses separate indexed username/name branches and hydrates request/count data only after limiting name candidates.';
