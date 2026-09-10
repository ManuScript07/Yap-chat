-- The first resolver used SECURITY INVOKER while reading public.profiles.
-- Profiles deliberately allow direct SELECT only for their owner, so a shared
-- username could resolve the current user but never another account. Keep the
-- REST-exposed function an invoker wrapper and move the narrow lookup behind a
-- private definer function, like the other protected profile reads.

create or replace function private.resolve_shared_profile_username_impl(
  shared_username text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text := lower(btrim(coalesce(shared_username, '')));
  resolved_user_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  perform private.require_active_account();

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

create or replace function public.resolve_shared_profile_username(
  shared_username text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.resolve_shared_profile_username_impl(shared_username);
$$;

revoke all on function private.resolve_shared_profile_username_impl(text)
  from public, anon;
revoke all on function public.resolve_shared_profile_username(text)
  from public, anon;

grant execute on function private.resolve_shared_profile_username_impl(text)
  to authenticated, service_role;
grant execute on function public.resolve_shared_profile_username(text)
  to authenticated, service_role;

comment on function public.resolve_shared_profile_username(text) is
  'Resolves an explicitly shared username link to an active profile id. The private implementation bypasses profile RLS but returns only the id and enforces account access and a 20/minute quota.';

notify pgrst, 'reload schema';
