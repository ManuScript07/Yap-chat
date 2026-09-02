-- Keep the per-minute quota compact without changing the already-applied
-- creation migration. The delete is scoped to the caller and uses the
-- table's (user_id, bucket_started_at) primary key.
create or replace function private.consume_nearby_people_read_quota()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_bucket timestamptz := date_trunc('minute', statement_timestamp());
  accepted_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.nearby_people_read_limits as quota (
    user_id, bucket_started_at, request_count
  ) values (current_user_id, current_bucket, 1)
  on conflict (user_id, bucket_started_at) do update
    set request_count = quota.request_count + 1
    where quota.request_count < 20
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'nearby_rate_limited';
  end if;

  delete from private.nearby_people_read_limits
  where user_id = current_user_id
    and bucket_started_at < current_bucket - interval '2 hours';
end;
$$;

revoke all on function private.consume_nearby_people_read_quota() from public, anon;
grant execute on function private.consume_nearby_people_read_quota()
  to authenticated, service_role;
