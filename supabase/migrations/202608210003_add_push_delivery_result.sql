alter table public.push_notification_outbox
add column delivery_result text
  check (delivery_result in (
    'delivered_to_fcm',
    'no_devices',
    'message_deleted'
  )),
add column delivered_device_count integer not null default 0
  check (delivered_device_count >= 0);

comment on column public.push_notification_outbox.delivery_result is
  'Final server-side outcome. delivered_to_fcm means FCM accepted the request, not that Android displayed it.';
comment on column public.push_notification_outbox.delivered_device_count is
  'Number of active device tokens for which FCM accepted the notification.';
