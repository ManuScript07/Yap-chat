-- Eight user-initiated feed reads per minute allow normal pagination while
-- retaining a strict server-side cap against repeated refreshes.
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
    where quota.request_count < 8
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'nearby_rate_limited';
  end if;

  delete from private.nearby_people_read_limits
  where user_id = current_user_id
    and bucket_started_at < current_bucket - interval '2 hours';
end;
$$;

notify pgrst, 'reload schema';
