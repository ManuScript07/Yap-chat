-- Friendship/request triggers already invalidate both participants' friend
-- lists (and direct-chat summaries for friendship changes). Add the peer id
-- to those events so an open viewed profile can refresh as well. This removes
-- the extra block-specific broadcast for the same mutation.

create or replace function private.broadcast_friend_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare first_user_id uuid; second_user_id uuid; conversation_id uuid;
begin
  if tg_table_name = 'friendships' and tg_op = 'DELETE' then
    first_user_id := old.user_one_id; second_user_id := old.user_two_id;
    delete from private.precise_location_exclusions exclusion
    where (exclusion.owner_user_id = first_user_id and exclusion.viewer_user_id = second_user_id)
       or (exclusion.owner_user_id = second_user_id and exclusion.viewer_user_id = first_user_id);
  elsif tg_table_name = 'friendships' then
    first_user_id := new.user_one_id; second_user_id := new.user_two_id;
  elsif tg_op = 'DELETE' then
    first_user_id := old.sender_id; second_user_id := old.recipient_id;
  else
    first_user_id := new.sender_id; second_user_id := new.recipient_id;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'table', tg_table_name,
      'operation', tg_op,
      'profile_id', second_user_id
    ),
    'changed',
    'user:' || first_user_id::text || ':friends',
    true
  );
  perform realtime.send(
    jsonb_build_object(
      'table', tg_table_name,
      'operation', tg_op,
      'profile_id', first_user_id
    ),
    'changed',
    'user:' || second_user_id::text || ':friends',
    true
  );

  if tg_table_name = 'friendships' then
    select id into conversation_id from public.conversations
    where user_one_id = first_user_id and user_two_id = second_user_id;
    if conversation_id is not null then
      perform realtime.send(
        jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'),
        'changed',
        'user:' || first_user_id::text || ':chats',
        true
      );
      perform realtime.send(
        jsonb_build_object('conversation_id', conversation_id, 'reason', 'friendship'),
        'changed',
        'user:' || second_user_id::text || ':chats',
        true
      );
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- A non-friend has no friendship/request trigger, so no realtime event is
-- sent for that case. Server-side checks still apply immediately; the client
-- receives the redacted state on its normal next synchronization.
create or replace function private.block_user_impl(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_block_target';
  end if;
  if not exists (select 1 from public.profiles where id = target_user_id) then
    raise exception using errcode = '22023', message = 'profile_not_found';
  end if;

  insert into public.user_blocks (blocker_user_id, blocked_user_id)
  values (current_user_id, target_user_id)
  on conflict do nothing;

  delete from public.friendships
  where user_one_id = least(current_user_id, target_user_id)
    and user_two_id = greatest(current_user_id, target_user_id);
  delete from public.friend_requests
  where pair_user_one_id = least(current_user_id, target_user_id)
    and pair_user_two_id = greatest(current_user_id, target_user_id);
end;
$$;

revoke all on function private.broadcast_friend_change()
  from public, anon, authenticated;
revoke all on function private.block_user_impl(uuid)
  from public, anon, authenticated;
grant execute on function private.broadcast_friend_change()
  to authenticated, service_role;
grant execute on function private.block_user_impl(uuid)
  to authenticated, service_role;
