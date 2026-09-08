-- The mobile bootstrap previously read public.profiles through PostgREST.
-- Keep the established own-row RLS contract explicit: a manual privilege
-- change must not turn a successful OAuth callback into an indefinite loading
-- screen. These privileges reveal no other profile because the existing RLS
-- policies and the global-ban restrictive policy still apply.
grant select, insert, update on table public.profiles to authenticated;
-- Trusted server-side work uses the service-role JWT. PostgreSQL still
-- requires an explicit table privilege even though that role bypasses RLS;
-- without it, a narrow server-side avatar lookup produces 42501 in PostgREST.
grant select on table public.profiles to service_role;

-- Narrow the client bootstrap to a single API operation. SECURITY INVOKER is
-- intentional: all reads and writes remain subject to the caller's own-row
-- RLS policies; no SECURITY DEFINER endpoint is exposed to signed-in users.
create or replace function public.get_or_create_my_profile(
  p_display_name text default null,
  p_birth_date date default null,
  p_avatar_url text default null
)
returns setof public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_at timestamptz := now();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  insert into public.profiles as profile (
    id,
    display_name,
    birth_date,
    avatar_url,
    terms_accepted_at,
    privacy_accepted_at
  )
  values (
    current_user_id,
    coalesce(nullif(btrim(p_display_name), ''), ''),
    p_birth_date,
    nullif(btrim(p_avatar_url), ''),
    accepted_at,
    accepted_at
  )
  on conflict (id) do update
  set
    display_name = case
      when nullif(btrim(profile.display_name), '') is null
        then excluded.display_name
      else profile.display_name
    end,
    birth_date = coalesce(profile.birth_date, excluded.birth_date),
    -- An avatar explicitly removed by its owner must never be restored from
    -- the OAuth provider during a later sign-in.
    avatar_url = case
      when not profile.yandex_avatar_disabled
        and profile.avatar_url is null
        and profile.avatar_storage_path is null
        then excluded.avatar_url
      else profile.avatar_url
    end,
    terms_accepted_at = coalesce(profile.terms_accepted_at, accepted_at),
    privacy_accepted_at = coalesce(profile.privacy_accepted_at, accepted_at);

  return query
  select profile.*
  from public.profiles profile
  where profile.id = current_user_id;
end;
$$;

revoke all on function public.get_or_create_my_profile(text, date, text)
  from public, anon;
grant execute on function public.get_or_create_my_profile(text, date, text)
  to authenticated, service_role;
