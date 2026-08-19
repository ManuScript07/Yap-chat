create or replace function public.hide_conversations(
  conversation_ids uuid[],
  cleared_before timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  effective_cleared_before timestamptz := least(cleared_before, now());
begin
  update public.conversation_members member
  set
    cleared_at = greatest(
      coalesce(member.cleared_at, '-infinity'::timestamptz),
      effective_cleared_before
    ),
    hidden_at = case
      when exists (
        select 1
        from public.messages message
        where message.conversation_id = member.conversation_id
          and message.deleted_for_everyone_at is null
          and message.created_at > greatest(
            coalesce(member.cleared_at, '-infinity'::timestamptz),
            effective_cleared_before
          )
      ) then null
      else now()
    end
  where member.user_id = auth.uid()
    and member.conversation_id = any(conversation_ids);

  perform realtime.send(
    jsonb_build_object('conversation_ids', conversation_ids, 'reason', 'hidden'),
    'changed',
    'user:' || auth.uid()::text || ':chats',
    true
  );
end;
$$;

grant execute on function public.hide_conversations(uuid[], timestamptz) to authenticated;
revoke all on function public.hide_conversations(uuid[], timestamptz) from public, anon;
