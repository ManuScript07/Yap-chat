create policy "Service role manages push notification outbox"
on public.push_notification_outbox
for all
to service_role
using (true)
with check (true);

comment on policy "Service role manages push notification outbox"
on public.push_notification_outbox is
  'Documents the server-only access model for the transactional push outbox.';

create index if not exists push_notification_outbox_conversation_id_idx
on public.push_notification_outbox (conversation_id);

create index if not exists push_notification_outbox_recipient_user_id_idx
on public.push_notification_outbox (recipient_user_id);

create index if not exists push_notification_outbox_sender_id_idx
on public.push_notification_outbox (sender_id);
