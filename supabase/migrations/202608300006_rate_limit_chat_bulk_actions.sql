-- Bulk chat actions are small, user-initiated writes. Limit each action kind
-- independently so a fast or modified client cannot repeatedly fan out work
-- across a large selection of conversations.
create table private.chat_bulk_action_write_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  action_name text not null check (action_name in ('hide', 'mark_read', 'mute')),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0),
  primary key (user_id, action_name)
);

revoke all on table private.chat_bulk_action_write_limits from public, anon, authenticated;

create function private.consume_chat_bulk_action_write_quota(requested_action text)
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if requested_action not in ('hide', 'mark_read', 'mute') then
    raise exception using errcode = '22023', message = 'invalid_chat_bulk_action';
  end if;
  insert into private.chat_bulk_action_write_limits as limits (
    user_id, action_name, window_started_at, request_count
  ) values (auth.uid(), requested_action, now(), 1)
  on conflict on constraint chat_bulk_action_write_limits_pkey do update set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  returning request_count into current_count;
  if current_count > 20 then
    raise exception using errcode = 'P0001', message = 'chat_bulk_action_rate_limited';
  end if;
end;
$$;

create or replace function public.mark_conversations_read(conversation_ids uuid[])
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if cardinality(conversation_ids) is null
     or cardinality(conversation_ids) < 1
     or cardinality(conversation_ids) > 50 then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;
  perform private.consume_chat_bulk_action_write_quota('mark_read');
  perform private.mark_conversations_read_impl(conversation_ids);
end;
$$;

create or replace function public.hide_conversations(
  conversation_ids uuid[],
  cleared_before timestamptz
)
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if cleared_before is null
     or cardinality(conversation_ids) is null
     or cardinality(conversation_ids) < 1
     or cardinality(conversation_ids) > 50 then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;
  perform private.consume_chat_bulk_action_write_quota('hide');
  perform private.hide_conversations_impl(conversation_ids, cleared_before);
end;
$$;

create or replace function public.toggle_conversations_mute(conversation_ids uuid[])
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if cardinality(conversation_ids) is null
     or cardinality(conversation_ids) < 1
     or cardinality(conversation_ids) > 50 then
    raise exception using errcode = '22023', message = 'invalid_conversation_selection';
  end if;
  perform private.consume_chat_bulk_action_write_quota('mute');
  perform private.toggle_conversations_mute_impl(conversation_ids);
end;
$$;

revoke all on function private.consume_chat_bulk_action_write_quota(text) from public, anon;
grant execute on function private.consume_chat_bulk_action_write_quota(text) to authenticated, service_role;
grant execute on function public.mark_conversations_read(uuid[]) to authenticated, service_role;
grant execute on function public.hide_conversations(uuid[], timestamptz) to authenticated, service_role;
grant execute on function public.toggle_conversations_mute(uuid[]) to authenticated, service_role;
