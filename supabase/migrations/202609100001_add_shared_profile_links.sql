-- A shared profile URL contains a mutable username, so resolve it to the
-- stable profile id only after authentication. This endpoint deliberately
-- bypasses search-by-username privacy: the owner explicitly gave the link to
-- the recipient. The subsequent profile read remains responsible for all
-- block redaction and visibility rules.

create table if not exists private.shared_profile_link_read_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default statement_timestamp(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.shared_profile_link_read_limits
  from public, anon, authenticated;

create or replace function private.consume_shared_profile_link_quota()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  insert into private.shared_profile_link_read_limits as limits (
    user_id, window_started_at, request_count
  ) values (current_user_id, statement_timestamp(), 1)
  on conflict on constraint shared_profile_link_read_limits_pkey do update
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
     or limits.request_count < 20
  returning request_count into accepted_count;

  if accepted_count is null then
    raise exception using errcode = '42901', message = 'shared_profile_link_rate_limited';
  end if;
end;
$$;

create or replace function public.resolve_shared_profile_username(
  shared_username text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_username text := lower(btrim(coalesce(shared_username, '')));
  resolved_user_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if normalized_username !~ '^[a-z0-9_]{3,24}$' then
    return null;
  end if;

  perform private.consume_shared_profile_link_quota();

  select profile.id into resolved_user_id
  from public.profiles profile
  where profile.username = normalized_username
    and profile.onboarding_completed
    and not private.is_account_globally_banned(profile.id)
  limit 1;

  return resolved_user_id;
end;
$$;

revoke all on function private.consume_shared_profile_link_quota()
  from public, anon, authenticated;
revoke all on function public.resolve_shared_profile_username(text)
  from public, anon;

grant execute on function private.consume_shared_profile_link_quota()
  to authenticated, service_role;
grant execute on function public.resolve_shared_profile_username(text)
  to authenticated, service_role;

comment on function public.resolve_shared_profile_username(text) is
  'Resolves an explicitly shared username link to a current active profile id; rate limited to twenty requests per minute per viewer.';

notify pgrst, 'reload schema';
