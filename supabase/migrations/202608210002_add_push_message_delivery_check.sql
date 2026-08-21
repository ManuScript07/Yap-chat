revoke select (id, deleted_for_everyone_at)
on public.messages
from service_role;

create or replace function public.is_push_message_deliverable(
  target_message_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.messages message
    where message.id = target_message_id
      and message.deleted_for_everyone_at is null
  );
$$;

revoke all on function public.is_push_message_deliverable(uuid)
from public, anon, authenticated;
grant execute on function public.is_push_message_deliverable(uuid)
to service_role;

comment on function public.is_push_message_deliverable(uuid) is
  'Server-only check used by the push worker before delivering a notification.';
