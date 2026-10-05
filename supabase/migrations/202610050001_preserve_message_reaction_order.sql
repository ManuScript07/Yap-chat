-- Keep chronological reaction/ avatar order through replacements and refreshes.
-- Existing message locking, idempotency, quotas, push and broadcast stay intact.
begin;
alter table private.message_reactions
  add column position bigint not null default 0 check (position >= 0);
-- Older rows only retain their last change revision, not the first placement.
-- Seed their current order from that revision; future replacements preserve it.
update private.message_reactions set position = revision where code is not null;

create or replace function private.message_reaction_state(target_message_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'version', coalesce((select revision from private.message_reaction_versions
      where message_id = target_message_id), 0),
    'reactions', coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'code', code, 'position', position)
      order by position, user_id) from private.message_reactions
      where message_id = target_message_id and code is not null), '[]'::jsonb),
    'user_revisions', coalesce((select jsonb_object_agg(user_id::text, revision)
      from private.message_reactions where message_id = target_message_id), '{}'::jsonb)
  );
$$;

create or replace function private.set_message_reaction_impl(
  target_conversation_id uuid, target_message_id uuid, reaction_code text,
  operation_id uuid, expected_user_revision bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.messages%rowtype;
  previous private.message_reactions%rowtype;
  member record;
  accepted integer;
  next_revision bigint;
  first_reaction boolean;
  state jsonb;
begin
  perform private.require_active_account();
  if operation_id is null or expected_user_revision is null or expected_user_revision < 0
      or (reaction_code is not null and reaction_code not in ('heart','like','cry','fire','mind_blown','poop')) then
    raise exception 'invalid_reaction' using errcode = '22023';
  end if;
  -- This quota also covers no-op/replayed calls. It is independent of message sends.
  insert into private.message_reaction_write_limits as limits
    (user_id, window_started_at, request_count)
  values (actor, statement_timestamp(), 1)
  on conflict (user_id) do update set
    window_started_at = case when limits.window_started_at <= statement_timestamp() - interval '1 minute'
      then statement_timestamp() else limits.window_started_at end,
    request_count = case when limits.window_started_at <= statement_timestamp() - interval '1 minute'
      then 1 else limits.request_count + 1 end
  where limits.window_started_at <= statement_timestamp() - interval '1 minute' or limits.request_count < 60
  returning request_count into accepted;
  if accepted is null then raise exception 'reaction_rate_limited' using errcode = '42901'; end if;

  -- Lock the message to serialize both participants without changing its body,
  -- timestamp, receipts or triggering the ordinary full-chat invalidation.
  select * into target from public.messages
    where id = target_message_id and conversation_id = target_conversation_id for update;
  if target.id is null or target.deleted_for_everyone_at is not null
      or not exists (select 1 from public.conversation_members cm
        where cm.conversation_id = target_conversation_id and cm.user_id = actor
          and target.created_at > coalesce(cm.cleared_at, '-infinity'::timestamptz))
      or exists (select 1 from public.message_hidden_for_users h
        where h.message_id = target_message_id and h.user_id = actor) then
    raise exception 'message_access_denied' using errcode = '42501';
  end if;
  if private.is_conversation_blocked_impl(target_conversation_id)
      or exists (select 1 from public.conversation_members cm
        where cm.conversation_id = target_conversation_id and cm.user_id <> actor
          and (private.is_account_globally_banned(cm.user_id)
            or private.is_account_pending_deletion(cm.user_id))) then
    raise exception 'conversation_blocked' using errcode = '42501';
  end if;
  select * into previous from private.message_reactions r
    where r.message_id = target_message_id and r.user_id = actor;
  if previous.operation_id = set_message_reaction_impl.operation_id
      or previous.code is not distinct from reaction_code then
    return jsonb_build_object('applied', true, 'state', private.message_reaction_state(target_message_id));
  end if;
  if coalesce(previous.revision, 0) <> expected_user_revision then
    return jsonb_build_object('applied', false, 'state', private.message_reaction_state(target_message_id));
  end if;
  if previous.updated_at > statement_timestamp() - interval '350 milliseconds' then
    raise exception 'reaction_rate_limited' using errcode = '42901';
  end if;
  first_reaction := reaction_code is not null and not coalesce(previous.has_reacted, false);
  insert into private.message_reaction_versions as v(message_id, revision)
  values (target_message_id, 1) on conflict (message_id) do update set revision = v.revision + 1
  returning revision into next_revision;
  insert into private.message_reactions as r(message_id, user_id, code, revision, operation_id, has_reacted, updated_at, position)
  values (target_message_id, actor, reaction_code, next_revision, operation_id,
    first_reaction or coalesce(previous.has_reacted, false), statement_timestamp(),
    case when previous.code is not null then previous.position else next_revision end)
  on conflict (message_id, user_id) do update set code = excluded.code, revision = excluded.revision,
    operation_id = excluded.operation_id, has_reacted = excluded.has_reacted, updated_at = excluded.updated_at,
    position = excluded.position;
  state := private.message_reaction_state(target_message_id);
  for member in select cm.user_id from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and target.created_at > coalesce(cm.cleared_at, '-infinity'::timestamptz)
      and not exists (select 1 from public.message_hidden_for_users h
        where h.message_id = target_message_id and h.user_id = cm.user_id)
  loop
    perform realtime.send(jsonb_build_object('conversation_id', target_conversation_id,
      'reason', 'reaction_changed', 'message_id', target_message_id, 'reaction_state', state),
      'changed', 'user:' || member.user_id::text || ':chats', true);
  end loop;
  if first_reaction and target.sender_id <> actor then
    insert into public.push_notification_outbox(reaction_message_id, reaction_code, conversation_id,
      recipient_user_id, sender_id, sender_name, message_type, message_text, message_created_at, notification_type)
    select target.id, reaction_code, target.conversation_id, target.sender_id, actor,
      p.display_name, target.type, left(target.text, 160), statement_timestamp(), 'message_reaction'
    from public.profiles p join public.conversation_members cm
      on cm.conversation_id = target.conversation_id and cm.user_id = target.sender_id
    where p.id = actor and not cm.is_muted
      and target.created_at > coalesce(cm.cleared_at, '-infinity'::timestamptz)
      and not exists (select 1 from public.message_hidden_for_users h
        where h.message_id = target.id and h.user_id = target.sender_id)
    on conflict (reaction_message_id, sender_id, recipient_user_id)
      do nothing;
  end if;
  return jsonb_build_object('applied', true, 'state', state);
end;
$$;

notify pgrst, 'reload schema';
commit;
