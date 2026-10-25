-- Stage 2a: an indexed per-member order and a bounded page/search RPC.
-- The installed clients' full-list and targeted RPCs retain their contracts.
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create table private.chat_list_catalog (
  user_id uuid not null,
  conversation_id uuid not null,
  activity_at timestamptz not null,
  latest_message_id uuid,
  is_visible boolean not null,
  primary key (user_id, conversation_id),
  foreign key (conversation_id, user_id)
    references public.conversation_members(conversation_id, user_id) on delete cascade
);
create index chat_list_catalog_member_idx
  on private.chat_list_catalog(conversation_id, user_id);
create index chat_list_catalog_visible_order_idx
  on private.chat_list_catalog(user_id, activity_at desc, conversation_id desc)
  where is_visible;
alter table private.chat_list_catalog enable row level security;
revoke all on private.chat_list_catalog from public, anon, authenticated;
grant all on private.chat_list_catalog to service_role;
create policy chat_list_catalog_service_only on private.chat_list_catalog
  to service_role using (true) with check (true);

create or replace function private.refresh_chat_list_catalog(
  conversation_ids uuid[], owner_ids uuid[] default null
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  member record;
  latest_id uuid;
  latest_at timestamptz;
begin
  if coalesce(cardinality(conversation_ids), 0) = 0 then return; end if;
  -- Lock before computing visibility, not after computing a stale snapshot.
  -- Member-row triggers restrict owner_ids to their already locked own row:
  -- two participants hiding a chat must never acquire each other's row lock.
  for member in
    select cm.user_id, cm.conversation_id, cm.hidden_at, cm.cleared_at,
      conversation.created_at
    from public.conversation_members cm
    join public.conversations conversation on conversation.id = cm.conversation_id
    where cm.conversation_id = any(conversation_ids)
      and (owner_ids is null or cm.user_id = any(owner_ids))
    order by cm.conversation_id, cm.user_id
    for update of cm
  loop
    latest_id := null;
    latest_at := null;
    if member.hidden_at is null then
      select message.id, message.created_at into latest_id, latest_at
      from public.messages message
      where message.conversation_id = member.conversation_id
        and message.deleted_for_everyone_at is null
        and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
        and not exists (
          select 1 from public.message_hidden_for_users hidden
          where hidden.message_id = message.id and hidden.user_id = member.user_id
        )
      order by message.created_at desc, message.id desc limit 1;
    end if;
    insert into private.chat_list_catalog as current
      (user_id, conversation_id, activity_at, latest_message_id, is_visible)
    values (member.user_id, member.conversation_id,
      coalesce(latest_at, member.created_at), latest_id, member.hidden_at is null)
    on conflict (user_id, conversation_id) do update set
      activity_at = excluded.activity_at,
      latest_message_id = excluded.latest_message_id,
      is_visible = excluded.is_visible
    where (current.activity_at, current.latest_message_id, current.is_visible)
      is distinct from (excluded.activity_at, excluded.latest_message_id, excluded.is_visible);
  end loop;
end;
$$;
revoke all on function private.refresh_chat_list_catalog(uuid[],uuid[])
from public, anon, authenticated;
grant execute on function private.refresh_chat_list_catalog(uuid[],uuid[]) to service_role;

create function private.chat_list_member_changed()
returns trigger language plpgsql security definer set search_path = ''
as $$ begin
  perform private.refresh_chat_list_catalog(array[new.conversation_id], array[new.user_id]);
  return null;
end; $$;
create trigger chat_list_member_insert after insert on public.conversation_members
  for each row execute function private.chat_list_member_changed();
create trigger chat_list_member_visibility after update of hidden_at, cleared_at
  on public.conversation_members for each row
  when (old.hidden_at is distinct from new.hidden_at or old.cleared_at is distinct from new.cleared_at)
  execute function private.chat_list_member_changed();

create function private.chat_list_messages_inserted()
returns trigger language plpgsql security definer set search_path = ''
as $$ begin
  perform private.refresh_chat_list_catalog(
    array(select distinct conversation_id from catalog_new_messages), null);
  return null;
end; $$;
create trigger chat_list_messages_insert after insert on public.messages
  referencing new table as catalog_new_messages
  for each statement execute function private.chat_list_messages_inserted();

create function private.chat_list_messages_updated()
returns trigger language plpgsql security definer set search_path = ''
as $$ begin
  perform private.refresh_chat_list_catalog(array(
    select distinct changed.conversation_id from (
      select coalesce(n.conversation_id, o.conversation_id) as conversation_id
      from catalog_new_messages n full join catalog_old_messages o using (id)
      where n.id is null or o.id is null
        or (n.deleted_for_everyone_at is null) <> (o.deleted_for_everyone_at is null)
        or n.created_at is distinct from o.created_at
        or n.conversation_id is distinct from o.conversation_id
      union
      select o.conversation_id from catalog_old_messages o
      join catalog_new_messages n using (id)
      where n.conversation_id is distinct from o.conversation_id
    ) changed
  ), null);
  return null;
end; $$;
create trigger chat_list_messages_update after update on public.messages
  referencing old table as catalog_old_messages new table as catalog_new_messages
  for each statement execute function private.chat_list_messages_updated();

create function private.chat_list_messages_deleted()
returns trigger language plpgsql security definer set search_path = ''
as $$ begin
  -- Normal 90-day cleanup removes tombstones: they cannot be the visible latest
  -- row. Do not recalculate one history for every purged receipt/attachment.
  perform private.refresh_chat_list_catalog(array(
    select distinct conversation_id from catalog_old_messages
    where deleted_for_everyone_at is null
  ), null);
  return null;
end; $$;
create trigger chat_list_messages_delete after delete on public.messages
  referencing old table as catalog_old_messages
  for each statement execute function private.chat_list_messages_deleted();

create function private.chat_list_hidden_changed()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare conversations uuid[]; owners uuid[];
begin
  if tg_op = 'INSERT' then
    select array_agg(distinct message.conversation_id), array_agg(distinct hidden.user_id)
      into conversations, owners
    from catalog_new_hidden hidden join public.messages message on message.id = hidden.message_id;
  elsif tg_op = 'DELETE' then
    select array_agg(distinct message.conversation_id), array_agg(distinct hidden.user_id)
      into conversations, owners
    from catalog_old_hidden hidden join public.messages message on message.id = hidden.message_id;
  else
    select array_agg(distinct message.conversation_id), array_agg(distinct hidden.user_id)
      into conversations, owners
    from (select message_id,user_id from catalog_old_hidden
      union select message_id,user_id from catalog_new_hidden) hidden
    join public.messages message on message.id = hidden.message_id;
  end if;
  perform private.refresh_chat_list_catalog(conversations, owners);
  return null;
end; $$;
create trigger chat_list_hidden_insert after insert on public.message_hidden_for_users
  referencing new table as catalog_new_hidden
  for each statement execute function private.chat_list_hidden_changed();
create trigger chat_list_hidden_delete after delete on public.message_hidden_for_users
  referencing old table as catalog_old_hidden
  for each statement execute function private.chat_list_hidden_changed();
create trigger chat_list_hidden_update after update on public.message_hidden_for_users
  referencing old table as catalog_old_hidden new table as catalog_new_hidden
  for each statement execute function private.chat_list_hidden_changed();

revoke all on function private.chat_list_member_changed(),
  private.chat_list_messages_inserted(), private.chat_list_messages_updated(),
  private.chat_list_messages_deleted(), private.chat_list_hidden_changed()
from public, anon, authenticated;

-- CREATE TRIGGER holds the member-table DDL lock until the migration commits.
-- Populate once from the same visibility rules; no read API repairs/writes data.
insert into private.chat_list_catalog(user_id,conversation_id,activity_at,latest_message_id,is_visible)
select member.user_id, member.conversation_id,
  coalesce(latest.created_at, conversation.created_at), latest.id, member.hidden_at is null
from public.conversation_members member
join public.conversations conversation on conversation.id = member.conversation_id
left join lateral (
  select message.id, message.created_at from public.messages message
  where member.hidden_at is null and message.conversation_id = member.conversation_id
    and message.deleted_for_everyone_at is null
    and message.created_at > coalesce(member.cleared_at, '-infinity'::timestamptz)
    and not exists(select 1 from public.message_hidden_for_users hidden
      where hidden.message_id=message.id and hidden.user_id=member.user_id)
  order by message.created_at desc, message.id desc limit 1
) latest on true;

create table private.chat_list_page_quota (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null check(request_count > 0)
);
alter table private.chat_list_page_quota enable row level security;
revoke all on private.chat_list_page_quota from public, anon, authenticated;
grant all on private.chat_list_page_quota to service_role;
create policy chat_list_page_quota_service_only on private.chat_list_page_quota
  to service_role using(true) with check(true);

create function private.get_chat_list_page_impl(
  after_activity_at timestamptz, after_conversation_id uuid,
  page_size integer, search_query text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(search_query,'')));
  pattern text;
  alias_candidate boolean;
  cursor_predicate text := '';
  selected_ids uuid[];
  selected_times timestamptz[];
  included_ids uuid[];
  more boolean;
  accepted integer;
  items jsonb;
begin
  if actor is null then raise exception using errcode='28000',message='authentication_required';end if;
  perform private.require_active_account();
  if page_size is null or page_size not between 1 and 50
    or char_length(normalized_query)>100
    or (after_activity_at is null) <> (after_conversation_id is null)
    or (after_activity_at is not null and not isfinite(after_activity_at)) then
    raise exception using errcode='22023',message='invalid_chat_list_page';
  end if;
  insert into private.chat_list_page_quota as quota(user_id,window_started_at,request_count)
  values(actor,statement_timestamp(),1)
  on conflict(user_id) do update set
    window_started_at=case when quota.window_started_at<=statement_timestamp()-interval '1 minute'
      then statement_timestamp() else quota.window_started_at end,
    request_count=case when quota.window_started_at<=statement_timestamp()-interval '1 minute'
      then 1 else quota.request_count+1 end
  where quota.window_started_at<=statement_timestamp()-interval '1 minute' or quota.request_count<120
  returning request_count into accepted;
  if accepted is null then raise exception using errcode='PT429',message='chat_list_page_rate_limited';end if;

  if after_activity_at is not null then
    cursor_predicate := ' and (catalog.activity_at,catalog.conversation_id)<($2,$3) ';
  end if;
  if normalized_query = '' then
    -- Only fixed SQL fragments are interpolated. All input stays in parameters.
    -- Separate first/next predicates make the tuple an actual index boundary.
    execute 'select array_agg(conversation_id order by activity_at desc,conversation_id desc),
      array_agg(activity_at order by activity_at desc,conversation_id desc) from (
        select catalog.conversation_id,catalog.activity_at from private.chat_list_catalog catalog
        where catalog.user_id=$1 and catalog.is_visible ' || cursor_predicate || '
        order by catalog.activity_at desc,catalog.conversation_id desc limit $4
      ) page'
      into selected_ids,selected_times using actor,after_activity_at,after_conversation_id,page_size+1;
  else
    pattern := replace(replace(replace(normalized_query,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_') || '%';
    alias_candidate := starts_with(lower('Заблокированный пользователь'),normalized_query)
      or starts_with(lower('Удалённый пользователь'),normalized_query);
    execute 'with candidates as materialized (
      select catalog.conversation_id,catalog.activity_at,peer.id as peer_id,peer.display_name
      from private.chat_list_catalog catalog
      join public.conversations conversation on conversation.id=catalog.conversation_id
      join public.profiles peer on peer.id=case when conversation.user_one_id=$1
        then conversation.user_two_id else conversation.user_one_id end
      where catalog.user_id=$1 and catalog.is_visible ' || cursor_predicate || '
        and (lower(peer.display_name) like $5 escape E''\\'' or $6)
    )
    select array_agg(conversation_id order by activity_at desc,conversation_id desc),
      array_agg(activity_at order by activity_at desc,conversation_id desc) from (
      select candidate.conversation_id,candidate.activity_at from candidates candidate
      where lower(case
        when private.is_account_globally_banned(candidate.peer_id) then ''Заблокированный пользователь''
        when private.is_account_pending_deletion(candidate.peer_id) then ''Удалённый пользователь''
        else candidate.display_name end) like $5 escape E''\\''
      order by candidate.activity_at desc,candidate.conversation_id desc limit $4
    ) page'
      into selected_ids,selected_times using actor,after_activity_at,after_conversation_id,page_size+1,pattern,alias_candidate;
  end if;

  more := coalesce(cardinality(selected_ids),0)>page_size;
  included_ids := selected_ids[1:page_size];
  if coalesce(cardinality(included_ids),0)=0 then
    items := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(to_jsonb(summary) || jsonb_build_object(
      'list_activity_at',selected_times[array_position(selected_ids,summary.id)])
      order by array_position(selected_ids,summary.id)), '[]'::jsonb)
      into items from private.get_chat_summaries_by_ids_impl(included_ids) summary;
  end if;
  return jsonb_build_object('items',items,'has_more',more,'query',normalized_query,
    'next_cursor',case when more then jsonb_build_object(
      'activity_at',selected_times[page_size], 'conversation_id',selected_ids[page_size],
      'query',normalized_query) else null end);
end;
$$;
create function public.get_chat_list_page(
  after_activity_at timestamptz default null, after_conversation_id uuid default null,
  page_size integer default 50, search_query text default ''
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.get_chat_list_page_impl(after_activity_at,after_conversation_id,page_size,search_query); $$;
revoke all on function private.get_chat_list_page_impl(timestamptz,uuid,integer,text) from public,anon;
revoke all on function public.get_chat_list_page(timestamptz,uuid,integer,text) from public,anon;
grant execute on function private.get_chat_list_page_impl(timestamptz,uuid,integer,text) to authenticated,service_role;
grant execute on function public.get_chat_list_page(timestamptz,uuid,integer,text) to authenticated,service_role;
