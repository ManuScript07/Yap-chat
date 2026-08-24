create function private.broadcast_public_profile_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  for recipient_id in
    select case
      when friendship.user_one_id = new.id then friendship.user_two_id
      else friendship.user_one_id
    end
    from public.friendships friendship
    where new.id in (friendship.user_one_id, friendship.user_two_id)
  loop
    perform realtime.send(
      jsonb_build_object(
        'reason', 'profile_updated',
        'profile_id', new.id
      ),
      'changed',
      'user:' || recipient_id::text || ':friends',
      true
    );
  end loop;

  for recipient_id in
    select distinct case
      when conversation.user_one_id = new.id then conversation.user_two_id
      else conversation.user_one_id
    end
    from public.conversations conversation
    where new.id in (conversation.user_one_id, conversation.user_two_id)
  loop
    perform realtime.send(
      jsonb_build_object(
        'reason', 'profile_updated',
        'profile_id', new.id
      ),
      'changed',
      'user:' || recipient_id::text || ':chats',
      true
    );
  end loop;

  return new;
end;
$$;

revoke all on function private.broadcast_public_profile_change()
from public, anon, authenticated;

create trigger profiles_broadcast_public_change
after update of
  username,
  display_name,
  avatar_url,
  avatar_storage_path,
  avatar_updated_at
on public.profiles
for each row
when (
  old.username is distinct from new.username
  or old.display_name is distinct from new.display_name
  or old.avatar_url is distinct from new.avatar_url
  or old.avatar_storage_path is distinct from new.avatar_storage_path
  or old.avatar_updated_at is distinct from new.avatar_updated_at
)
execute function private.broadcast_public_profile_change();

comment on function private.broadcast_public_profile_change() is
  'Notifies friend and chat peers when public profile identity fields change.';
