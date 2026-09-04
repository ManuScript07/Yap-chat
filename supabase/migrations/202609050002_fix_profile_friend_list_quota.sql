-- Keep databases that already applied the pagination migration in sync with
-- its corrected quota upsert. The constraint name avoids ambiguity between the
-- function argument and the table's target_user_id column.
create or replace function private.consume_profile_friend_list_read_quota(
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_count integer;
begin
  if current_user_id is null or target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.profile_friend_list_read_limits as limits (
    viewer_user_id,
    target_user_id,
    window_started_at,
    request_count
  ) values (
    current_user_id,
    target_user_id,
    statement_timestamp(),
    1
  )
  on conflict on constraint profile_friend_list_read_limits_pkey do update
  set
    window_started_at = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then statement_timestamp()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= statement_timestamp() - interval '1 minute'
        then 1
      else limits.request_count + 1
    end
  where limits.window_started_at <= statement_timestamp() - interval '1 minute'
     or limits.request_count < 12
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'profile_friends_rate_limited';
  end if;
end;
$$;

revoke all on function private.consume_profile_friend_list_read_quota(uuid)
  from public, anon, authenticated;
