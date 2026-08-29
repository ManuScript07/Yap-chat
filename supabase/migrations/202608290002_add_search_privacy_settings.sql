-- Account-level discovery settings are kept outside the exposed API schema.
-- A missing row intentionally means that all discovery methods are enabled.
create table private.search_privacy_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  search_by_username boolean not null default true,
  search_by_phone boolean not null default true,
  search_by_name boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

revoke all on table private.search_privacy_settings
from public, anon, authenticated;

create function private.get_my_search_privacy_settings_impl()
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(settings.search_by_username, true),
         coalesce(settings.search_by_phone, true),
         coalesce(settings.search_by_name, true)
  from (select auth.uid() as user_id) viewer
  left join private.search_privacy_settings settings
    on settings.user_id = viewer.user_id
  where viewer.user_id is not null;
$$;

create function private.update_my_search_privacy_settings_impl(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  insert into private.search_privacy_settings (
    user_id,
    search_by_username,
    search_by_phone,
    search_by_name,
    updated_at
  )
  values (
    auth.uid(),
    is_searchable_by_username,
    is_searchable_by_phone,
    is_searchable_by_name,
    now()
  )
  on conflict (user_id) do update
  set search_by_username = excluded.search_by_username,
      search_by_phone = excluded.search_by_phone,
      search_by_name = excluded.search_by_name,
      updated_at = now();

  return query
  select settings.search_by_username,
         settings.search_by_phone,
         settings.search_by_name
  from private.search_privacy_settings settings
  where settings.user_id = auth.uid();
end;
$$;

revoke all on function private.get_my_search_privacy_settings_impl()
from public, anon;
revoke all on function private.update_my_search_privacy_settings_impl(
  boolean, boolean, boolean
)
from public, anon;
grant execute on function private.get_my_search_privacy_settings_impl()
to authenticated, service_role;
grant execute on function private.update_my_search_privacy_settings_impl(
  boolean, boolean, boolean
) to authenticated, service_role;

create function public.get_my_search_privacy_settings()
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_my_search_privacy_settings_impl();
$$;

create function public.update_my_search_privacy_settings(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.update_my_search_privacy_settings_impl(
    is_searchable_by_username,
    is_searchable_by_phone,
    is_searchable_by_name
  );
$$;

revoke all on function public.get_my_search_privacy_settings()
from public, anon;
revoke all on function public.update_my_search_privacy_settings(
  boolean, boolean, boolean
)
from public, anon;
grant execute on function public.get_my_search_privacy_settings()
to authenticated, service_role;
grant execute on function public.update_my_search_privacy_settings(
  boolean, boolean, boolean
) to authenticated, service_role;

-- Preserve the existing parsing, ordering and limits. Only the profile-level
-- visibility check is added; an existing friend is always allowed through it.
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
        and (
          coalesce((
            select settings.search_by_username
            from private.search_privacy_settings settings
            where settings.user_id = profile.id
          ), true)
          or exists (
            select 1
            from public.friendships friendship
            where friendship.user_one_id = least(profile.id, current_user_id)
              and friendship.user_two_id = greatest(profile.id, current_user_id)
          )
        )
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
      and (
        coalesce((
          select settings.search_by_name
          from private.search_privacy_settings settings
          where settings.user_id = profile.id
        ), true)
        or exists (
          select 1
          from public.friendships friendship
          where friendship.user_one_id = least(profile.id, current_user_id)
            and friendship.user_two_id = greatest(profile.id, current_user_id)
        )
      )
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

-- Phone discovery has the same account boundary, while retaining the older
-- discoverable_by_phone switch and allowing an existing friend through both.
create or replace function private.match_contact_phones_impl(phone_numbers text[])
returns table (
  phone_number text,
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
  with viewer as materialized (
    select auth.uid() as id
  ),
  normalized_input as (
    select normalized.phone_number, min(source.position) as position
    from unnest(coalesce(phone_numbers, array[]::text[]))
      with ordinality as source(phone_number, position)
    cross join lateral (
      select private.normalize_phone(source.phone_number) as phone_number
    ) normalized
    where normalized.phone_number is not null
    group by normalized.phone_number
    order by min(source.position)
    limit 500
  ),
  input as materialized (
    select
      normalized_input.phone_number,
      normalized_input.position,
      private.phone_lookup_hash(normalized_input.phone_number) as lookup_hash
    from normalized_input
  )
  select
    input.phone_number,
    profile.id,
    request.id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when profile.show_friends_count
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    case
      when friendship.id is not null then 'friend'
      when request.sender_id = viewer.id then 'outgoing'
      when request.recipient_id = viewer.id then 'incoming'
      else 'none'
    end
  from input
  cross join viewer
  join public.profiles profile
    on profile.phone_lookup_hash = input.lookup_hash
   and profile.onboarding_completed
   and profile.id <> viewer.id
  left join private.search_privacy_settings privacy
    on privacy.user_id = profile.id
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, viewer.id)
   and friendship.user_two_id = greatest(profile.id, viewer.id)
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, viewer.id)
   and request.pair_user_two_id = greatest(profile.id, viewer.id)
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where viewer.id is not null
    and (
      profile.discoverable_by_phone
      or friendship.id is not null
    )
    and (
      coalesce(privacy.search_by_phone, true)
      or friendship.id is not null
    )
  order by input.position;
$$;

revoke all on function private.search_friend_candidates_impl(text, integer)
from public, anon;
grant execute on function private.search_friend_candidates_impl(text, integer)
to authenticated, service_role;
revoke all on function private.match_contact_phones_impl(text[])
from public, anon;
grant execute on function private.match_contact_phones_impl(text[])
to authenticated, service_role;
