-- A member may keep at most one hundred visible direct conversations. Hidden
-- conversations do not count: opening one is a user-initiated restore and is
-- therefore subject to the same limit. Incoming messages remain allowed to
-- restore a hidden conversation, even when the recipient is already at the
-- limit, so a sender can never be prevented from delivering a valid message.
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
  existing_conversation_id uuid;
  current_member_is_hidden boolean;
  visible_conversation_count integer;
begin
  if current_user_id is null
     or peer_user_id is null
     or current_user_id = peer_user_id then
    raise exception using errcode = '22023', message = 'invalid_conversation_members';
  end if;

  if not exists (select 1 from public.profiles where id = peer_user_id) then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  -- Serialise only attempts made by the same account. Without this lock two
  -- concurrent clients could both observe 99 visible conversations and create
  -- two new ones.
  perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));

  first_user_id := least(current_user_id, peer_user_id);
  second_user_id := greatest(current_user_id, peer_user_id);

  select conversation.id, member.hidden_at is not null
  into existing_conversation_id, current_member_is_hidden
  from public.conversations conversation
  left join public.conversation_members member
    on member.conversation_id = conversation.id
   and member.user_id = current_user_id
  where conversation.user_one_id = first_user_id
    and conversation.user_two_id = second_user_id;

  if existing_conversation_id is not null
     and coalesce(current_member_is_hidden, true) = false then
    return existing_conversation_id;
  end if;

  select count(*)::integer
  into visible_conversation_count
  from public.conversation_members member
  where member.user_id = current_user_id
    and member.hidden_at is null;

  if visible_conversation_count >= 100 then
    raise exception using errcode = 'P0001', message = 'chat_limit_reached';
  end if;

  if existing_conversation_id is null then
    insert into public.conversations (user_one_id, user_two_id, created_by)
    values (first_user_id, second_user_id, current_user_id)
    on conflict (user_one_id, user_two_id) do update
      set updated_at = public.conversations.updated_at
    returning id into existing_conversation_id;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values
    (existing_conversation_id, first_user_id),
    (existing_conversation_id, second_user_id)
  on conflict do nothing;

  update public.conversation_members member
  set hidden_at = null
  where member.conversation_id = existing_conversation_id
    and member.user_id = current_user_id;

  return existing_conversation_id;
end;
$$;

revoke all on function private.create_direct_conversation_impl(uuid)
from public, anon;
grant execute on function private.create_direct_conversation_impl(uuid)
to authenticated, service_role;
