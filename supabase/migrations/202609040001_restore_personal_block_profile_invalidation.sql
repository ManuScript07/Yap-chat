-- A personal block must invalidate an already open viewed profile for both
-- participants. The rate-limit migration redefined block_user_impl without
-- carrying over the explicit block broadcast. Relying only on friendship and
-- request delete triggers leaves non-friends without any invalidation and
-- makes the result depend on unrelated synchronization.
--
-- During a newly created block, suppress those generic delete broadcasts and
-- emit one block-specific event below instead. It updates the same caches and
-- chat summaries, but avoids duplicate realtime events and duplicate refreshes
-- for former friends/request participants.

create or replace function private.broadcast_friend_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  first_user_id uuid;
  second_user_id uuid;
  conversation_id uuid;
  is_personal_block_change boolean :=
    coalesce(current_setting('app.personal_block_change', true), 'false') = 'true';
begin
  if tg_table_name = 'friendships' and tg_op = 'DELETE' then
    first_user_id := old.user_one_id;
    second_user_id := old.user_two_id;
    delete from private.precise_location_exclusions exclusion
    where (exclusion.owner_user_id = first_user_id and exclusion.viewer_user_id = second_user_id)
       or (exclusion.owner_user_id = second_user_id and exclusion.viewer_user_id = first_user_id);
  elsif tg_table_name = 'friendships' then
    first_user_id := new.user_one_id;
    second_user_id := new.user_two_id;
  elsif tg_op = 'DELETE' then
    first_user_id := old.sender_id;
    second_user_id := old.recipient_id;
  else
    first_user_id := new.sender_id;
    second_user_id := new.recipient_id;
  end if;

  if not is_personal_block_change then
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
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function private.block_user_impl(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  created_block boolean := false;
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_block_target';
  end if;
  if not exists (select 1 from public.profiles where id = target_user_id) then
    raise exception using errcode = '22023', message = 'profile_not_found';
  end if;

  perform private.lock_user_block_pair(current_user_id, target_user_id);

  if not exists (
    select 1 from public.user_blocks block
    where block.blocker_user_id = current_user_id
      and block.blocked_user_id = target_user_id
  ) then
    perform private.consume_user_block_write_quota();
    insert into public.user_blocks (blocker_user_id, blocked_user_id)
    values (current_user_id, target_user_id);
    created_block := true;
  end if;

  -- A repeated click is an idempotent no-op. Keep the old cleanup behaviour
  -- without manufacturing a new realtime refresh for an unchanged block.
  if created_block then
    perform set_config('app.personal_block_change', 'true', true);
  end if;

  delete from public.friendships
  where user_one_id = least(current_user_id, target_user_id)
    and user_two_id = greatest(current_user_id, target_user_id);
  delete from public.friend_requests
  where pair_user_one_id = least(current_user_id, target_user_id)
    and pair_user_two_id = greatest(current_user_id, target_user_id);

  if created_block then
    perform private.broadcast_block_change_impl(
      current_user_id,
      target_user_id,
      'blocked'
    );
  end if;
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
