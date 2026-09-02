-- The public wrappers are SECURITY INVOKER, while direct reads from these
-- relationship tables are deliberately denied by RLS (RPC only). Resolve the
-- peer in narrowly scoped private helpers instead of treating an RLS-hidden
-- row as a blocked conversation or missing request.
create or replace function private.get_direct_conversation_peer_impl(
  target_conversation_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select peer_member.user_id
  from public.conversation_members self_member
  join public.conversation_members peer_member
    on peer_member.conversation_id = self_member.conversation_id
   and peer_member.user_id <> self_member.user_id
  where self_member.conversation_id = $1
    and self_member.user_id = auth.uid()
  limit 1;
$$;

create or replace function private.get_pending_friend_request_peer_impl(
  target_request_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select request.sender_id
  from public.friend_requests request
  where request.id = $1
    and request.recipient_id = auth.uid();
$$;

create or replace function public.send_chat_message(
  message_id uuid,
  target_conversation_id uuid,
  message_type text,
  message_text text default '',
  message_latitude double precision default null,
  message_longitude double precision default null,
  reply_message_id uuid default null,
  message_attachments jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  peer_user_id := private.get_direct_conversation_peer_impl(
    target_conversation_id
  );
  if peer_user_id is null
     or private.is_account_globally_banned(peer_user_id)
     or private.is_conversation_blocked_impl(target_conversation_id) then
    raise exception using errcode = '42501', message = 'conversation_blocked';
  end if;
  return private.send_chat_message_impl(
    message_id, target_conversation_id, message_type, message_text,
    message_latitude, message_longitude, reply_message_id, message_attachments
  );
end;
$$;

create or replace function public.respond_friend_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  peer_user_id uuid;
begin
  peer_user_id := private.get_pending_friend_request_peer_impl(
    target_request_id
  );
  if peer_user_id is null then
    raise exception using errcode = 'P0001', message = 'friend_request_not_found';
  end if;
  if accept_request and private.is_account_globally_banned(peer_user_id) then
    raise exception using errcode = '42501', message = 'friend_request_blocked';
  end if;
  perform private.respond_friend_request_impl(target_request_id, accept_request);
end;
$$;

revoke all on function private.get_direct_conversation_peer_impl(uuid)
  from public, anon;
revoke all on function private.get_pending_friend_request_peer_impl(uuid)
  from public, anon;
grant execute on function private.get_direct_conversation_peer_impl(uuid)
  to authenticated, service_role;
grant execute on function private.get_pending_friend_request_peer_impl(uuid)
  to authenticated, service_role;
revoke all on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
  from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean)
  from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, text, text, double precision, double precision, uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.respond_friend_request(uuid, boolean)
  to authenticated, service_role;
