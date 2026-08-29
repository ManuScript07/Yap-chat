-- Opening a direct chat after it was deleted is a restore operation for the
-- current member, not a request for a second conversation. The old function
-- returned the existing conversation while leaving this member hidden, so
-- the client could not resolve the id and never reached send_chat_message().
create or replace function private.create_direct_conversation_impl(peer_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  first_user_id uuid;
  second_user_id uuid;
  created_conversation_id uuid;
begin
  if current_user_id is null or peer_user_id is null or current_user_id = peer_user_id then
    raise exception 'invalid_conversation_members';
  end if;

  if not exists (
    select 1 from public.profiles where id = peer_user_id
  ) then
    raise exception 'profile_not_found';
  end if;

  first_user_id := least(current_user_id, peer_user_id);
  second_user_id := greatest(current_user_id, peer_user_id);

  insert into public.conversations (
    user_one_id,
    user_two_id,
    created_by
  )
  values (
    first_user_id,
    second_user_id,
    current_user_id
  )
  on conflict (user_one_id, user_two_id) do update
  set updated_at = public.conversations.updated_at
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (created_conversation_id, first_user_id),
    (created_conversation_id, second_user_id)
  on conflict do nothing;

  update public.conversation_members as member
  set hidden_at = null
  where member.conversation_id = created_conversation_id
    and member.user_id = current_user_id;

  return created_conversation_id;
end;
$$;

revoke all on function private.create_direct_conversation_impl(uuid)
from public, anon;
grant execute on function private.create_direct_conversation_impl(uuid)
to authenticated, service_role;
