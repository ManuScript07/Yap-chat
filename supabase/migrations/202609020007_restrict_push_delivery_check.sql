-- The push worker calls this via the service-role client. Mobile sessions
-- must not be able to probe message delivery through this SECURITY DEFINER
-- function.
revoke all on function public.is_push_message_deliverable(uuid)
  from public, anon, authenticated;
grant execute on function public.is_push_message_deliverable(uuid)
  to service_role;
