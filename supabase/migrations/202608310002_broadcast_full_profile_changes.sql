-- Friends and chat peers already listen on these private channels. Include
-- every public profile field rendered by the viewed-profile screen. A gallery
-- save also updates profiles.updated_at, so it sends one refresh event.
drop trigger if exists profiles_broadcast_public_change on public.profiles;

create trigger profiles_broadcast_public_change
after update of
  username,
  display_name,
  birth_date,
  gender,
  bio,
  avatar_url,
  avatar_storage_path,
  avatar_updated_at,
  updated_at
on public.profiles
for each row
when (
  old.username is distinct from new.username
  or old.display_name is distinct from new.display_name
  or old.birth_date is distinct from new.birth_date
  or old.gender is distinct from new.gender
  or old.bio is distinct from new.bio
  or old.avatar_url is distinct from new.avatar_url
  or old.avatar_storage_path is distinct from new.avatar_storage_path
  or old.avatar_updated_at is distinct from new.avatar_updated_at
  or old.updated_at is distinct from new.updated_at
)
execute function private.broadcast_public_profile_change();
