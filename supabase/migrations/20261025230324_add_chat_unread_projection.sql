-- Materialize only currently unread incoming messages, not message content.
-- Counts and their evidence change atomically; repeated visibility changes
-- remove/insert a key once instead of guessing a +/- delta from old snapshots.
-- CLI runners may autocommit each top-level statement. Keep all schema changes,
-- backfill and locks in one atomic command instead of relying on the runner.
-- Set the statement deadline before that command starts; SET LOCAL inside it
-- alone would not establish a deadline for an already running statement.
set statement_timeout='120s';
do $chat_unread_migration$
begin
set local lock_timeout='5s';
lock table public.conversation_members,public.messages,public.message_receipts,
  public.message_hidden_for_users in share row exclusive mode;

create table private.chat_unread_counts(
  conversation_id uuid not null,
  user_id uuid not null,
  unread_count bigint not null default 0 check(unread_count>=0),
  is_visible boolean not null,
  is_muted boolean not null,
  primary key(conversation_id,user_id),
  foreign key(conversation_id,user_id) references public.conversation_members(conversation_id,user_id) on delete cascade
);
create index chat_unread_counts_badge_idx on private.chat_unread_counts(user_id)
  include(unread_count) where is_visible and not is_muted;
create table private.chat_unread_messages(
  message_id uuid not null,
  user_id uuid not null,
  conversation_id uuid not null,
  created_at timestamptz not null,
  primary key(message_id,user_id),
  foreign key(conversation_id,user_id) references private.chat_unread_counts(conversation_id,user_id) on delete cascade
);
create index chat_unread_messages_member_idx
  on private.chat_unread_messages(conversation_id,user_id,created_at);
-- Deliberately no FK to messages: the message DELETE transition trigger removes
-- evidence in one batch and adjusts counts. Cascading each key first would lose
-- that evidence and add one counter write per physically removed message.
alter table private.chat_unread_counts enable row level security;
alter table private.chat_unread_messages enable row level security;
revoke all on private.chat_unread_counts,private.chat_unread_messages from public,anon,authenticated;
grant all on private.chat_unread_counts,private.chat_unread_messages to service_role;
create policy chat_unread_counts_service_only on private.chat_unread_counts
  to service_role using(true) with check(true);
create policy chat_unread_messages_service_only on private.chat_unread_messages
  to service_role using(true) with check(true);

create or replace function private.sync_chat_unread_messages_impl(message_ids uuid[],owner_ids uuid[],remove_kind text)
returns void language plpgsql security definer set search_path='' as $$
declare conversations uuid[];removed jsonb;added jsonb;
begin
  if coalesce(cardinality(message_ids),0)=0 then return;end if;
  if remove_kind is not null and remove_kind not in('read','hide','clear','insert')then
    raise exception using errcode='22023',message='invalid_unread_sync_kind';
  end if;
  -- Parameterized PK probes also find the former conversation of a moved or
  -- physically deleted message through its retained private evidence.
  with requested as materialized(select distinct unnest(message_ids) as id)
  select array_agg(distinct affected.conversation_id) into conversations from(
    select m.conversation_id from requested r cross join lateral(
      select message.conversation_id from public.messages message where message.id=r.id and remove_kind is distinct from 'clear' limit 1
    )m
    union
    select u.conversation_id from requested r cross join lateral(
      select evidence.conversation_id from private.chat_unread_messages evidence
      where evidence.message_id=r.id and(owner_ids is null or evidence.user_id=any(owner_ids))offset 0
    )u
  )affected;
  if coalesce(cardinality(conversations),0)=0 then return;end if;

  -- Lock membership before reading receipt/hide/clear state, not a stale
  -- aggregate afterward. A receipt/hide locks only its affected owner(s).
  perform cm.conversation_id from public.conversation_members cm
  where cm.conversation_id=any(conversations) and(owner_ids is null or cm.user_id=any(owner_ids))
  order by cm.conversation_id,cm.user_id for update;

  if remove_kind='insert' then
    removed:='[]'::jsonb;
  elsif remove_kind in('read','hide','clear')then
    -- The triggering fact is still checked by key. Cross-products of batch
    -- owners/IDs must never erase an unmarked participant's unread key.
    with deleted as(
      delete from private.chat_unread_messages u
      where u.message_id=any(message_ids)and(owner_ids is null or u.user_id=any(owner_ids))
        and case remove_kind
          when 'read'then coalesce((select true from public.message_receipts r where r.message_id=u.message_id and r.user_id=u.user_id limit 1),false)
          when 'hide'then coalesce((select true from public.message_hidden_for_users h where h.message_id=u.message_id and h.user_id=u.user_id limit 1),false)
          when 'clear'then exists(select 1 from public.conversation_members cm where cm.conversation_id=u.conversation_id and cm.user_id=u.user_id
            and u.created_at<=coalesce(cm.cleared_at,'-infinity'::timestamptz))
        end
      returning u.conversation_id,u.user_id
    ),grouped as(select conversation_id,user_id,-count(*)as delta from deleted group by conversation_id,user_id)
    select coalesce(jsonb_agg(to_jsonb(grouped)),'[]'::jsonb)into removed from grouped;
  else
  with deleted as(
    delete from private.chat_unread_messages u
    where u.message_id=any(message_ids) and(owner_ids is null or u.user_id=any(owner_ids))
      and not exists(
        select 1 from public.messages m join public.conversation_members cm
          on cm.conversation_id=m.conversation_id and cm.user_id=u.user_id
        where m.id=u.message_id and m.conversation_id=u.conversation_id and m.created_at=u.created_at
          and m.sender_id<>u.user_id and m.deleted_for_everyone_at is null
          and m.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
          and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=u.user_id)
          and not coalesce((select true from public.message_receipts r where r.message_id=m.id and r.user_id=u.user_id limit 1),false)
      )returning u.conversation_id,u.user_id
  ),grouped as(select conversation_id,user_id,-count(*) as delta from deleted group by conversation_id,user_id)
  select coalesce(jsonb_agg(to_jsonb(grouped)),'[]'::jsonb) into removed from grouped;
  end if;

  -- A separate command sees keys removed above, including timestamp/owner
  -- changes. DELETE+INSERT of the same key in sibling CTEs is not ordered.
  if remove_kind in('read','hide','clear')then
    added:='[]'::jsonb;
  else
  with inserted as(
    insert into private.chat_unread_messages(message_id,user_id,conversation_id,created_at)
    select m.id,cm.user_id,m.conversation_id,m.created_at
    from(select distinct unnest(message_ids) as id)requested
    join public.messages m on m.id=requested.id
    join public.conversation_members cm on cm.conversation_id=m.conversation_id and cm.user_id<>m.sender_id
    where(owner_ids is null or cm.user_id=any(owner_ids)) and m.deleted_for_everyone_at is null
      and m.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
      and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=cm.user_id)
      and not coalesce((select true from public.message_receipts r where r.message_id=m.id and r.user_id=cm.user_id limit 1),false)
    on conflict(message_id,user_id) do nothing
    returning conversation_id,user_id
  ),grouped as(select conversation_id,user_id,count(*) as delta from inserted group by conversation_id,user_id)
  select coalesce(jsonb_agg(to_jsonb(grouped)),'[]'::jsonb) into added from grouped;
  end if;

  with changes as(
    select conversation_id,user_id,sum(delta)::bigint as delta
    from jsonb_to_recordset(removed||added) as d(conversation_id uuid,user_id uuid,delta bigint)
    group by conversation_id,user_id having sum(delta)<>0
  )update private.chat_unread_counts c set unread_count=c.unread_count+d.delta
    from changes d where c.conversation_id=d.conversation_id and c.user_id=d.user_id;
end;$$;
revoke all on function private.sync_chat_unread_messages_impl(uuid[],uuid[],text) from public,anon,authenticated;
grant execute on function private.sync_chat_unread_messages_impl(uuid[],uuid[],text) to service_role;
create or replace function private.sync_chat_unread_messages(message_ids uuid[],owner_ids uuid[] default null)
returns void language sql security invoker set search_path='' as $$
  select private.sync_chat_unread_messages_impl(message_ids,owner_ids,null);
$$;
revoke all on function private.sync_chat_unread_messages(uuid[],uuid[]) from public,anon,authenticated;
grant execute on function private.sync_chat_unread_messages(uuid[],uuid[]) to service_role;

-- Explicit admin/backfill repair, never called by application reads. Also lets
-- bulk local fixtures that deliberately disable triggers restore invariants.
create function private.rebuild_chat_unread_projection(conversation_ids uuid[])
returns void language plpgsql security definer set search_path='' as $$
begin
  if conversation_ids is null or array_ndims(conversation_ids)>1 then
    raise exception using errcode='22023',message='invalid_unread_rebuild_selection';
  end if;
  if cardinality(conversation_ids)=0 then return;end if;
  perform cm.conversation_id from public.conversation_members cm where cm.conversation_id=any(conversation_ids)
    order by cm.conversation_id,cm.user_id for update;
  delete from private.chat_unread_messages where conversation_id=any(conversation_ids);
  insert into private.chat_unread_counts as current(conversation_id,user_id,unread_count,is_visible,is_muted)
  select conversation_id,user_id,0,hidden_at is null,is_muted from public.conversation_members
    where conversation_id=any(conversation_ids)
  on conflict(conversation_id,user_id)do update set unread_count=0,is_visible=excluded.is_visible,is_muted=excluded.is_muted
  where(current.unread_count,current.is_visible,current.is_muted)is distinct from(0::bigint,excluded.is_visible,excluded.is_muted);
  insert into private.chat_unread_messages(message_id,user_id,conversation_id,created_at)
  select m.id,cm.user_id,m.conversation_id,m.created_at
  from public.conversation_members cm join public.messages m on m.conversation_id=cm.conversation_id and cm.user_id<>m.sender_id
  where cm.conversation_id=any(conversation_ids) and m.deleted_for_everyone_at is null
    and m.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
    and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=cm.user_id)
    and not exists(select 1 from public.message_receipts r where r.message_id=m.id and r.user_id=cm.user_id);
  update private.chat_unread_counts c set unread_count=counts.total
  from(select conversation_id,user_id,count(*)as total from private.chat_unread_messages
    where conversation_id=any(conversation_ids)group by conversation_id,user_id)counts
  where c.conversation_id=counts.conversation_id and c.user_id=counts.user_id;
end;$$;
revoke all on function private.rebuild_chat_unread_projection(uuid[]) from public,anon,authenticated;
grant execute on function private.rebuild_chat_unread_projection(uuid[]) to service_role;
-- One-time backfill under this migration's write locks.
perform private.rebuild_chat_unread_projection(array(select distinct conversation_id from public.conversation_members));

create or replace function private.chat_unread_members_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare ids uuid[];owners uuid[];may_add boolean;
begin
  if tg_op='INSERT' then
    insert into private.chat_unread_counts(conversation_id,user_id,is_visible,is_muted)
    select conversation_id,user_id,hidden_at is null,is_muted from unread_new_members
    on conflict(conversation_id,user_id) do nothing;
    select array_agg(distinct m.id),array_agg(distinct cm.user_id) into ids,owners
    from unread_new_members cm join public.messages m on m.conversation_id=cm.conversation_id;
  else
    if not exists(select 1 from unread_new_members n join unread_old_members o using(conversation_id,user_id)
      where(n.hidden_at is null,n.is_muted,n.cleared_at)is distinct from(o.hidden_at is null,o.is_muted,o.cleared_at))then return null;end if;
    update private.chat_unread_counts c set is_visible=n.hidden_at is null,is_muted=n.is_muted
      from unread_new_members n where c.conversation_id=n.conversation_id and c.user_id=n.user_id
      and(c.is_visible,c.is_muted)is distinct from(n.hidden_at is null,n.is_muted);
    select coalesce(bool_or(coalesce(n.cleared_at,'-infinity'::timestamptz)<coalesce(o.cleared_at,'-infinity'::timestamptz)),false)
      into may_add from unread_new_members n join unread_old_members o using(conversation_id,user_id);
    with changed as materialized(
      select n.conversation_id,n.user_id,n.cleared_at as next_clear,o.cleared_at as previous_clear
      from unread_new_members n join unread_old_members o using(conversation_id,user_id)
      where n.cleared_at is distinct from o.cleared_at
    ),affected as(
      -- Advancing clear touches existing unread keys only; no history scan.
      select u.message_id,c.user_id from changed c join private.chat_unread_messages u
        on u.conversation_id=c.conversation_id and u.user_id=c.user_id
        and u.created_at<=coalesce(c.next_clear,'-infinity'::timestamptz)
      union
      -- Lowering clear (an administrative restore) can make a range eligible.
      select m.id,c.user_id from changed c join public.messages m on m.conversation_id=c.conversation_id
        and m.created_at>coalesce(c.next_clear,'-infinity'::timestamptz)
        and m.created_at<=coalesce(c.previous_clear,'-infinity'::timestamptz)
      where coalesce(c.next_clear,'-infinity'::timestamptz)<coalesce(c.previous_clear,'-infinity'::timestamptz)
    )select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from affected;
  end if;
  perform private.sync_chat_unread_messages_impl(ids,owners,case when tg_op='UPDATE'and not may_add then 'clear'else null end);
  return null;
end;$$;
create trigger chat_unread_member_insert after insert on public.conversation_members
  referencing new table as unread_new_members for each statement execute function private.chat_unread_members_changed();
create trigger chat_unread_member_update after update on public.conversation_members
  referencing old table as unread_old_members new table as unread_new_members
  for each statement execute function private.chat_unread_members_changed();

create or replace function private.chat_unread_messages_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare ids uuid[];
begin
  if tg_op='INSERT' then
    select array_agg(id) into ids from unread_new_messages;
  elsif tg_op='DELETE' then
    -- Tombstones normally have no unread evidence. Avoid touching any history
    -- or locking memberships during their normal 90-day physical cleanup.
    select array_agg(distinct u.message_id) into ids from unread_old_messages o
      join private.chat_unread_messages u on u.message_id=o.id;
  else
    select array_agg(distinct changed.id) into ids from(
      select coalesce(n.id,o.id) as id from unread_new_messages n full join unread_old_messages o using(id)
      where n.id is null or o.id is null or(n.conversation_id,n.sender_id,n.created_at,n.deleted_for_everyone_at is null)
        is distinct from(o.conversation_id,o.sender_id,o.created_at,o.deleted_for_everyone_at is null)
    )changed;
  end if;
  perform private.sync_chat_unread_messages_impl(ids,null,case when tg_op='INSERT'then 'insert'else null end);
  return null;
end;$$;
create trigger chat_unread_message_insert after insert on public.messages
  referencing new table as unread_new_messages for each statement execute function private.chat_unread_messages_changed();
create trigger chat_unread_message_update after update on public.messages
  referencing old table as unread_old_messages new table as unread_new_messages
  for each statement execute function private.chat_unread_messages_changed();
create trigger chat_unread_message_delete after delete on public.messages
  referencing old table as unread_old_messages for each statement execute function private.chat_unread_messages_changed();

create or replace function private.chat_unread_receipts_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare ids uuid[];owners uuid[];remove_only boolean:=false;
begin
  if tg_op='INSERT' then
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from unread_new_receipts;
    -- Scalar PK probes remain bounded even after rolled-back bulk writes have
    -- changed table size without refreshing planner statistics.
    select not exists(select 1 from unread_new_receipts n where not coalesce((
      select true from public.message_receipts r where r.message_id=n.message_id and r.user_id=n.user_id limit 1),false))into remove_only;
  elsif tg_op='DELETE' then
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from unread_old_receipts;
  else
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from(
      (select message_id,user_id from unread_new_receipts except select message_id,user_id from unread_old_receipts)
      union
      (select message_id,user_id from unread_old_receipts except select message_id,user_id from unread_new_receipts)
    )changed;
  end if;
  perform private.sync_chat_unread_messages_impl(ids,owners,case when remove_only then 'read'else null end);
  return null;
end;$$;
create trigger chat_unread_receipt_insert after insert on public.message_receipts
  referencing new table as unread_new_receipts for each statement execute function private.chat_unread_receipts_changed();
create trigger chat_unread_receipt_update after update on public.message_receipts
  referencing old table as unread_old_receipts new table as unread_new_receipts
  for each statement execute function private.chat_unread_receipts_changed();
create trigger chat_unread_receipt_delete after delete on public.message_receipts
  referencing old table as unread_old_receipts for each statement execute function private.chat_unread_receipts_changed();

create or replace function private.chat_unread_hides_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare ids uuid[];owners uuid[];remove_only boolean:=false;
begin
  if tg_op='INSERT' then
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from unread_new_hides;
    select not exists(select 1 from unread_new_hides n where not coalesce((
      select true from public.message_hidden_for_users h where h.message_id=n.message_id and h.user_id=n.user_id limit 1),false))into remove_only;
  elsif tg_op='DELETE' then
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from unread_old_hides;
  else
    select array_agg(distinct message_id),array_agg(distinct user_id) into ids,owners from(
      (select message_id,user_id from unread_new_hides except select message_id,user_id from unread_old_hides)
      union
      (select message_id,user_id from unread_old_hides except select message_id,user_id from unread_new_hides)
    )changed;
  end if;
  perform private.sync_chat_unread_messages_impl(ids,owners,case when remove_only then 'hide'else null end);
  return null;
end;$$;
create trigger chat_unread_hide_insert after insert on public.message_hidden_for_users
  referencing new table as unread_new_hides for each statement execute function private.chat_unread_hides_changed();
create trigger chat_unread_hide_update after update on public.message_hidden_for_users
  referencing old table as unread_old_hides new table as unread_new_hides
  for each statement execute function private.chat_unread_hides_changed();
create trigger chat_unread_hide_delete after delete on public.message_hidden_for_users
  referencing old table as unread_old_hides for each statement execute function private.chat_unread_hides_changed();
revoke all on function private.chat_unread_members_changed(),private.chat_unread_messages_changed(),
  private.chat_unread_receipts_changed(),private.chat_unread_hides_changed() from public,anon,authenticated;

create function private.get_chat_unread_total_impl()
returns bigint language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();result bigint;
begin
  if actor is null then raise exception using errcode='28000',message='authentication_required';end if;
  perform private.require_active_account();
  select coalesce(sum(c.unread_count),0)::bigint into result from private.chat_unread_counts c
    where c.user_id=actor and c.is_visible and not c.is_muted;
  return result;
end;$$;
revoke all on function private.get_chat_unread_total_impl() from public,anon,authenticated;
grant execute on function private.get_chat_unread_total_impl() to service_role;

create function private.get_chat_unread_state_impl(conversation_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare items jsonb;actor uuid:=auth.uid();
begin
  if actor is null then raise exception using errcode='28000',message='authentication_required';end if;
  perform private.require_active_account();
  if conversation_ids is null or array_ndims(conversation_ids)>1 or cardinality(conversation_ids)>50 then
    raise exception using errcode='22023',message='invalid_chat_summary_selection';
  end if;
  if array_position(conversation_ids,null)is not null then
    raise exception using errcode='22023',message='invalid_chat_summary_selection';
  end if;
  if cardinality(conversation_ids)=0 then
    perform private.consume_chat_summary_refresh_quota(1);
    items:='[]'::jsonb;
  else
    select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into items
      from private.get_chat_summaries_by_ids_impl(conversation_ids)s;
  end if;
  return jsonb_build_object('items',items,'unread_total',private.get_chat_unread_total_impl());
end;$$;
create function public.get_chat_unread_state(conversation_ids uuid[] default array[]::uuid[])
returns jsonb language sql security invoker set search_path='' as $$
  select private.get_chat_unread_state_impl(conversation_ids);
$$;
revoke all on function private.get_chat_unread_state_impl(uuid[]),public.get_chat_unread_state(uuid[]) from public,anon;
grant execute on function private.get_chat_unread_state_impl(uuid[]),public.get_chat_unread_state(uuid[]) to authenticated,service_role;

-- The shape/permissions/quotas of installed clients' selected-row RPC stay intact.
create or replace function private.get_chat_summaries_by_ids_impl(conversation_ids uuid[])
returns table (
  id uuid, peer_id uuid, peer_username text, peer_display_name text,
  peer_avatar_url text, peer_avatar_storage_path text, last_message_id uuid,
  last_message_text text, last_message_type text, last_message_sender_id uuid,
  last_message_at timestamptz, unread_count bigint, is_muted boolean,
  peer_last_seen_at timestamptz, peer_shows_last_seen boolean,
  blocked_by_me boolean, blocked_by_peer boolean, peer_is_globally_banned boolean,
  peer_is_deleted boolean, peer_is_online boolean
)
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  row_cost integer;
begin
  if actor is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  perform private.require_active_account();
  if coalesce(cardinality(conversation_ids), 0) not between 1 and 50
     or array_ndims(conversation_ids) <> 1
     or array_position(conversation_ids, null) is not null then
    raise exception using errcode = '22023', message = 'invalid_chat_summary_selection';
  end if;
  select count(distinct requested_id)::integer into row_cost
  from unnest(conversation_ids) requested(requested_id);

  perform private.consume_chat_summary_refresh_quota(row_cost);

  return query
  -- Authorization and requested IDs are applied BEFORE history/unread work.
  with visible_members as materialized (
    select member.conversation_id, member.cleared_at, member.is_muted
    from public.conversation_members member
    where member.user_id = actor and member.hidden_at is null
      and member.conversation_id = any(conversation_ids)
  )
  select conversation.id, peer.id,
    case when flags.redact then '' else peer.username end,
    case when flags.globally_banned then 'Заблокированный пользователь'
         when flags.pending_deletion then 'Удалённый пользователь'
         else peer.display_name end,
    case when flags.redact then null else peer.avatar_url end,
    case when flags.redact then null else peer.avatar_storage_path end,
    latest_message.id, latest_message.text, latest_message.type,
    latest_message.sender_id,
    coalesce(latest_message.created_at, conversation.created_at),
    coalesce((select counts.unread_count from private.chat_unread_counts counts
      where counts.conversation_id=member.conversation_id and counts.user_id=actor),0::bigint),
    member.is_muted,
    case when not flags.redact and seen.visible then peer.last_seen_at else null end,
    not flags.redact and seen.visible,
    flags.blocked_by_me, flags.blocked_by_peer, flags.globally_banned,
    flags.pending_deletion,
    not flags.redact and private.is_user_online(peer.id)
  from visible_members member
  join public.conversations conversation on conversation.id = member.conversation_id
  join public.profiles peer on peer.id = case when conversation.user_one_id = actor
    then conversation.user_two_id else conversation.user_one_id end
  left join private.search_privacy_settings privacy on privacy.user_id = peer.id
  left join public.friendships friendship
    on friendship.user_one_id = least(peer.id, actor)
   and friendship.user_two_id = greatest(peer.id, actor)
  left join lateral (
    select message.id, message.text, message.type, message.sender_id, message.created_at
    from public.messages message
    where message.conversation_id = member.conversation_id
      and message.deleted_for_everyone_at is null
      and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
      and not exists (select 1 from public.message_hidden_for_users hidden
        where hidden.message_id = message.id and hidden.user_id = actor)
    order by message.created_at desc, message.id desc limit 1
  ) latest_message on true
  cross join lateral (
    select private.is_account_globally_banned(peer.id) as globally_banned,
      private.is_account_pending_deletion(peer.id) as pending_deletion,
      private.is_blocked_by_impl(actor, peer.id) as blocked_by_me,
      private.is_blocked_by_impl(peer.id, actor) as blocked_by_peer
  ) flags_raw
  cross join lateral (
    select flags_raw.*,
      (flags_raw.globally_banned or flags_raw.pending_deletion or flags_raw.blocked_by_peer) as redact
  ) flags
  cross join lateral (
    select coalesce(privacy.last_seen_visibility, 'all') = 'all'
      or (coalesce(privacy.last_seen_visibility, 'all') = 'friends' and friendship.id is not null) as visible
  ) seen
  order by coalesce(latest_message.created_at, conversation.created_at) desc, conversation.id desc;
end;
$$;

-- Keep the page implementation and cursor/search contract; add the unfiltered
-- badge total in the same response, never an extra periodic client request.
alter function private.get_chat_list_page_impl(timestamptz,uuid,integer,text)
  rename to get_chat_list_page_without_unread_impl;
revoke all on function private.get_chat_list_page_without_unread_impl(timestamptz,uuid,integer,text)
  from public,anon,authenticated;
create function private.get_chat_list_page_impl(
  after_activity_at timestamptz,after_conversation_id uuid,page_size integer,search_query text
)returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.get_chat_list_page_without_unread_impl(after_activity_at,after_conversation_id,page_size,search_query);
  return result||jsonb_build_object('unread_total',private.get_chat_unread_total_impl());
end;$$;
revoke all on function private.get_chat_list_page_impl(timestamptz,uuid,integer,text) from public,anon;
grant execute on function private.get_chat_list_page_impl(timestamptz,uuid,integer,text) to authenticated,service_role;
create or replace function public.get_chat_list_page(
  after_activity_at timestamptz default null,after_conversation_id uuid default null,
  page_size integer default 50,search_query text default ''
)returns jsonb language sql security invoker set search_path='' as $$
  select private.get_chat_list_page_impl(after_activity_at,after_conversation_id,page_size,search_query);
$$;
notify pgrst,'reload schema';
end;
$chat_unread_migration$;
reset statement_timeout;
