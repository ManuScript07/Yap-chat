grant select (id, deleted_for_everyone_at)
on public.messages
to service_role;

comment on column public.messages.deleted_for_everyone_at is
  'Read by the server-side push worker to avoid notifying about recalled messages.';
