-- Fixed reaction codes, one choice per member, on the existing user channel.
create table private.message_reaction_versions (
  message_id uuid primary key references public.messages(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0)
);
create table private.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  code text check (code in ('heart','like','cry','fire','mind_blown','poop')),
  revision bigint not null default 0,
  operation_id uuid not null,
  has_reacted boolean not null default false,
  updated_at timestamptz not null default statement_timestamp(),
  primary key (message_id, user_id)
);
create index message_reactions_user_id_idx on private.message_reactions(user_id, message_id);
create table private.message_reaction_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null
);
revoke all on private.message_reactions, private.message_reaction_versions,
  private.message_reaction_write_limits from public, anon, authenticated;

create function private.message_reaction_state(target_message_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'version', coalesce((select revision from private.message_reaction_versions
      where message_id = target_message_id), 0),
    'reactions', coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'code', code)
      order by user_id) from private.message_reactions
      where message_id = target_message_id and code is not null), '[]'::jsonb),
    'user_revisions', coalesce((select jsonb_object_agg(user_id::text, revision)
      from private.message_reactions where message_id = target_message_id), '{}'::jsonb)
  );
$$;
revoke all on function private.message_reaction_state(uuid) from public, anon, authenticated;

alter table public.push_notification_outbox
  add column reaction_message_id uuid references public.messages(id) on delete cascade,
  add column reaction_code text,
  drop constraint push_notification_outbox_notification_type_check,
  drop constraint push_notification_outbox_payload_check,
  add constraint push_notification_outbox_notification_type_check
    check (notification_type in ('chat_message','friend_request','message_reaction')),
  add constraint push_notification_outbox_payload_check check (
    (notification_type = 'chat_message' and message_id is not null and conversation_id is not null
      and friend_request_id is null and reaction_message_id is null)
    or (notification_type = 'friend_request' and message_id is null and conversation_id is null
      and friend_request_id is not null and reaction_message_id is null)
    or (notification_type = 'message_reaction' and message_id is null and conversation_id is not null
      and friend_request_id is null and reaction_message_id is not null
      and reaction_code is not null
      and reaction_code in ('heart','like','cry','fire','mind_blown','poop'))
  );
create unique index push_notification_outbox_reaction_unique
  on public.push_notification_outbox(reaction_message_id, sender_id, recipient_user_id);

create function private.set_message_reaction_impl(
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
  insert into private.message_reactions as r(message_id, user_id, code, revision, operation_id, has_reacted, updated_at)
  values (target_message_id, actor, reaction_code, next_revision, operation_id,
    first_reaction or coalesce(previous.has_reacted, false), statement_timestamp())
  on conflict (message_id, user_id) do update set code = excluded.code, revision = excluded.revision,
    operation_id = excluded.operation_id, has_reacted = excluded.has_reacted, updated_at = excluded.updated_at;
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
create function public.set_message_reaction(target_conversation_id uuid, target_message_id uuid,
  reaction_code text, operation_id uuid, expected_user_revision bigint default 0)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.set_message_reaction_impl(target_conversation_id, target_message_id,
    reaction_code, operation_id, expected_user_revision);
$$;
revoke all on function private.set_message_reaction_impl(uuid,uuid,text,uuid,bigint) from public, anon;
revoke all on function public.set_message_reaction(uuid,uuid,text,uuid,bigint) from public, anon;
grant execute on function private.set_message_reaction_impl(uuid,uuid,text,uuid,bigint),
  public.set_message_reaction(uuid,uuid,text,uuid,bigint) to authenticated;

-- Page projections include reactions without a second request per message.
alter function public.get_conversation_messages(uuid,timestamptz,uuid,integer)
  rename to get_conversation_messages_without_reactions;
alter function public.get_conversation_messages_without_reactions(uuid,timestamptz,uuid,integer) set schema private;
create function private.get_conversation_messages_with_reactions_impl(
  target_conversation_id uuid, before_created_at timestamptz, before_message_id uuid, page_size integer)
returns table(id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision, reply_to_message_id uuid,
  created_at timestamptz, read_at timestamptz, attachments jsonb,
  reply_sender_id uuid, reply_type text, reply_text text, reaction_state jsonb)
language sql stable security definer set search_path = '' as $$
  select m.*, private.message_reaction_state(m.id)
  from private.get_conversation_messages(target_conversation_id, before_created_at,
    before_message_id, least(greatest(coalesce(page_size,60),1),60)) m;
$$;
create function public.get_conversation_messages(target_conversation_id uuid,
  before_created_at timestamptz default null, before_message_id uuid default null, page_size integer default 60)
returns table(id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision, reply_to_message_id uuid,
  created_at timestamptz, read_at timestamptz, attachments jsonb,
  reply_sender_id uuid, reply_type text, reply_text text, reaction_state jsonb)
language plpgsql security invoker set search_path = '' as $$
begin
  perform private.require_active_account();
  perform private.consume_network_read_quota('conversation_messages',60);
  return query select * from private.get_conversation_messages_with_reactions_impl(
    target_conversation_id,before_created_at,before_message_id,page_size);
end; $$;

alter function public.get_conversation_message_window(uuid,uuid,timestamptz,uuid,integer)
  rename to get_conversation_message_window_without_reactions;
alter function public.get_conversation_message_window_without_reactions(uuid,uuid,timestamptz,uuid,integer) set schema private;
create function private.get_conversation_window_with_reactions_impl(
  target_conversation_id uuid, target_message_id uuid, after_created_at timestamptz,
  after_message_id uuid, page_size integer)
returns table(id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision, reply_to_message_id uuid,
  created_at timestamptz, read_at timestamptz, attachments jsonb,
  reply_sender_id uuid, reply_type text, reply_text text, reaction_state jsonb)
language sql stable security definer set search_path = '' as $$
  select m.*, private.message_reaction_state(m.id)
  from private.get_conversation_message_window_impl(target_conversation_id,target_message_id,
    after_created_at,after_message_id,page_size) m;
$$;
create function public.get_conversation_message_window(target_conversation_id uuid,
  target_message_id uuid default null, after_created_at timestamptz default null,
  after_message_id uuid default null, page_size integer default 60)
returns table(id uuid, conversation_id uuid, sender_id uuid, type text, text text,
  latitude double precision, longitude double precision, reply_to_message_id uuid,
  created_at timestamptz, read_at timestamptz, attachments jsonb,
  reply_sender_id uuid, reply_type text, reply_text text, reaction_state jsonb)
language plpgsql security invoker set search_path = '' as $$
begin
  perform private.require_active_account();
  perform private.consume_network_read_quota('conversation_messages',60);
  return query select * from private.get_conversation_window_with_reactions_impl(
    target_conversation_id,target_message_id,after_created_at,after_message_id,page_size);
end; $$;

-- Replaces the existing ID-only visibility request for viewed cache pages.
create function private.get_visible_message_states_impl(target_conversation_id uuid, message_ids uuid[])
returns table(id uuid, reaction_state jsonb)
language sql stable security definer set search_path = '' as $$
  select m.id, private.message_reaction_state(m.id) from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id and cm.user_id = auth.uid()
  where m.conversation_id = target_conversation_id and m.id = any(message_ids)
    and m.deleted_for_everyone_at is null
    and m.created_at > coalesce(cm.cleared_at,'-infinity'::timestamptz)
    and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=auth.uid());
$$;
create function public.get_visible_conversation_message_states(target_conversation_id uuid,message_ids uuid[])
returns table(id uuid,reaction_state jsonb)
language plpgsql security invoker set search_path = '' as $$
begin
  perform private.require_active_account();
  if coalesce(cardinality(message_ids),0) > 60 then raise exception 'message_page_too_large' using errcode='22023'; end if;
  perform private.consume_network_read_quota('conversation_messages',60);
  return query select * from private.get_visible_message_states_impl(target_conversation_id,message_ids);
end; $$;

revoke all on function private.get_conversation_messages_with_reactions_impl(uuid,timestamptz,uuid,integer),
  private.get_conversation_window_with_reactions_impl(uuid,uuid,timestamptz,uuid,integer),
  private.get_visible_message_states_impl(uuid,uuid[]),
  public.get_conversation_messages(uuid,timestamptz,uuid,integer),
  public.get_conversation_message_window(uuid,uuid,timestamptz,uuid,integer),
  public.get_visible_conversation_message_states(uuid,uuid[]) from public, anon;
grant execute on function private.get_conversation_messages_with_reactions_impl(uuid,timestamptz,uuid,integer),
  private.get_conversation_window_with_reactions_impl(uuid,uuid,timestamptz,uuid,integer),
  private.get_visible_message_states_impl(uuid,uuid[]),
  public.get_conversation_messages(uuid,timestamptz,uuid,integer),
  public.get_conversation_message_window(uuid,uuid,timestamptz,uuid,integer),
  public.get_visible_conversation_message_states(uuid,uuid[]) to authenticated;

create function public.is_push_reaction_deliverable(target_message_id uuid, reactor_user_id uuid, expected_code text)
returns boolean language sql stable security definer set search_path='' as $$
  select public.is_push_message_deliverable(target_message_id)
    and exists(select 1 from private.message_reactions r
      join public.messages m on m.id=r.message_id
      join public.conversation_members cm on cm.conversation_id=m.conversation_id and cm.user_id=m.sender_id
      where r.message_id=target_message_id and r.user_id=reactor_user_id and r.code=expected_code
        and not cm.is_muted and m.created_at > coalesce(cm.cleared_at,'-infinity'::timestamptz)
        and not private.is_account_globally_banned(reactor_user_id)
        and not private.is_account_pending_deletion(reactor_user_id)
        and not private.is_account_globally_banned(m.sender_id)
        and not private.is_account_pending_deletion(m.sender_id)
        and not private.is_user_pair_blocked_impl(reactor_user_id,m.sender_id)
        and not exists(select 1 from public.message_hidden_for_users h
          where h.message_id=m.id and h.user_id=m.sender_id));
$$;
revoke all on function public.is_push_reaction_deliverable(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.is_push_reaction_deliverable(uuid,uuid,text) to service_role;
notify pgrst,'reload schema';
