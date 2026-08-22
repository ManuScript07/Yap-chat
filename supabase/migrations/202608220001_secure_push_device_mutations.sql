alter function public.register_push_device(text, text, text)
  security invoker;
alter function public.unregister_push_device(text)
  security invoker;

grant select, insert, update, delete
on public.push_devices
to authenticated;

drop policy if exists "Authenticated users manage own push devices"
on public.push_devices;
create policy "Authenticated users manage own push devices"
on public.push_devices
for all
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

comment on table public.push_devices is
  'FCM device registry. RLS restricts authenticated sessions to their own device records; the application uses RPC functions for mutations.';
