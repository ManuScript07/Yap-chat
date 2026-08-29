-- Resolve address-book entries for newly added friends without invalidating
-- negative matches for every other contact. The client never receives a
-- friend's phone number: it only receives a profile when its own contact
-- number matches a verified friendship.
create or replace function private.match_new_friend_contact_phones_impl(
  phone_numbers text[],
  friend_user_ids uuid[]
)
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
  ),
  verified_friends as materialized (
    select distinct requested.id
    from unnest(coalesce(friend_user_ids, array[]::uuid[])) as requested(id)
    cross join viewer
    join public.friendships friendship
      on friendship.user_one_id = least(requested.id, viewer.id)
     and friendship.user_two_id = greatest(requested.id, viewer.id)
    where viewer.id is not null
      and requested.id <> viewer.id
    limit 100
  )
  select
    input.phone_number,
    profile.id,
    null::uuid as request_id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when profile.show_friends_count
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    'friend'::text as relationship
  from input
  join public.profiles profile
    on profile.phone_lookup_hash = input.lookup_hash
   and profile.onboarding_completed
  join verified_friends friend
    on friend.id = profile.id
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  order by input.position;
$$;

revoke all on function private.match_new_friend_contact_phones_impl(text[], uuid[])
from public, anon;
grant execute on function private.match_new_friend_contact_phones_impl(text[], uuid[])
to authenticated, service_role;

create or replace function public.match_new_friend_contact_phones(
  phone_numbers text[],
  friend_user_ids uuid[]
)
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
security invoker
set search_path = ''
as $$
  select * from private.match_new_friend_contact_phones_impl(
    phone_numbers,
    friend_user_ids
  );
$$;

revoke all on function public.match_new_friend_contact_phones(text[], uuid[])
from public, anon;
grant execute on function public.match_new_friend_contact_phones(text[], uuid[])
to authenticated, service_role;
