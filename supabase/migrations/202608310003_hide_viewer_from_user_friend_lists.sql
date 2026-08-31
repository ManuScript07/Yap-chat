create or replace function private.get_user_profile_friends_impl(target_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text
)
language sql stable security definer set search_path = ''
as $$
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
  where auth.uid() is not null
    and target_user_id is not null
    and (friendship.user_one_id = target_user_id or friendship.user_two_id = target_user_id)
    and peer.id <> auth.uid()
    and peer.onboarding_completed
  order by peer.display_name, peer.id;
$$;
