-- Keep an immutable legal-document version next to each acceptance timestamp.
-- The public links live in Storage, but a profile must retain the version it
-- accepted even after app-content.json later points at a newer PDF.

alter table private.app_public_content
  add column if not exists terms_version text not null default 'terms-of-use-v1',
  add column if not exists privacy_policy_version text not null default 'privacy-policy-v1';

alter table private.app_public_content
  drop constraint if exists app_public_content_terms_version_format,
  drop constraint if exists app_public_content_privacy_policy_version_format,
  add constraint app_public_content_terms_version_format
    check (terms_version ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  add constraint app_public_content_privacy_policy_version_format
    check (privacy_policy_version ~ '^[a-z0-9][a-z0-9._-]{0,79}$');

-- `draft-v1` was only a schema placeholder, not an accepted document. A
-- nullable version is therefore deliberate: the timestamp remains the proof
-- of consent, and the version records which document was accepted.
alter table public.profiles
  alter column terms_version drop not null,
  alter column terms_version drop default,
  add column if not exists privacy_policy_version text;

alter table public.profiles
  drop constraint if exists profiles_terms_version_format,
  drop constraint if exists profiles_privacy_policy_version_format,
  add constraint profiles_terms_version_format
    check (
      terms_version is null
      or terms_version ~ '^[a-z0-9][a-z0-9._-]{0,79}$'
    ),
  add constraint profiles_privacy_policy_version_format
    check (
      privacy_policy_version is null
      or privacy_policy_version ~ '^[a-z0-9][a-z0-9._-]{0,79}$'
    );

-- Do not send one profile-realtime invalidation per historical row merely for
-- this internal audit backfill. The trigger is restored in the same atomic
-- migration transaction.
do $$
begin
  if exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.profiles'::regclass
      and trigger_row.tgname = 'profiles_broadcast_public_change'
      and not trigger_row.tgisinternal
  ) then
    alter table public.profiles disable trigger profiles_broadcast_public_change;
  end if;
end;
$$;

with active_versions as (
  select
    content.terms_version,
    content.privacy_policy_version
  from private.app_public_content content
  where content.singleton
)
update public.profiles profile
set
  terms_version = case
    when profile.terms_accepted_at is null then null
    when profile.terms_version is null or profile.terms_version = 'draft-v1'
      then coalesce(
        (select terms_version from active_versions),
        'terms-of-use-v1'
      )
    else profile.terms_version
  end,
  privacy_policy_version = case
    when profile.privacy_accepted_at is null then null
    when profile.privacy_policy_version is null
      then coalesce(
        (select privacy_policy_version from active_versions),
        'privacy-policy-v1'
      )
    else profile.privacy_policy_version
  end
where profile.terms_version is not null
   or profile.privacy_policy_version is not null
   or profile.terms_accepted_at is not null
   or profile.privacy_accepted_at is not null;

do $$
begin
  if exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.profiles'::regclass
      and trigger_row.tgname = 'profiles_broadcast_public_change'
      and not trigger_row.tgisinternal
  ) then
    alter table public.profiles enable trigger profiles_broadcast_public_change;
  end if;
end;
$$;

-- This is intentionally private: it gives the authenticated profile-bootstrap
-- a server-owned snapshot without reintroducing a public SECURITY DEFINER RPC.
create or replace function private.get_active_legal_document_versions()
returns table (
  terms_version text,
  privacy_policy_version text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(
      (
        select nullif(content.terms_version, '')
        from private.app_public_content content
        where content.singleton
      ),
      'terms-of-use-v1'
    ),
    coalesce(
      (
        select nullif(content.privacy_policy_version, '')
        from private.app_public_content content
        where content.singleton
      ),
      'privacy-policy-v1'
    );
$$;

revoke all on function private.get_active_legal_document_versions()
  from public, anon;
grant execute on function private.get_active_legal_document_versions()
  to authenticated, service_role;

-- The function remains SECURITY INVOKER: own-row RLS keeps governing the
-- profile write. It only obtains the active versions through the private,
-- read-only helper above.
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
  active_terms_version text;
  active_privacy_policy_version text;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select
    legal.terms_version,
    legal.privacy_policy_version
  into active_terms_version, active_privacy_policy_version
  from private.get_active_legal_document_versions() legal;

  insert into public.profiles as profile (
    id,
    display_name,
    birth_date,
    avatar_url,
    terms_accepted_at,
    terms_version,
    privacy_accepted_at,
    privacy_policy_version
  )
  values (
    current_user_id,
    coalesce(nullif(btrim(p_display_name), ''), ''),
    p_birth_date,
    nullif(btrim(p_avatar_url), ''),
    accepted_at,
    active_terms_version,
    accepted_at,
    active_privacy_policy_version
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
    terms_version = case
      when profile.terms_accepted_at is null then active_terms_version
      else profile.terms_version
    end,
    privacy_accepted_at = coalesce(profile.privacy_accepted_at, accepted_at),
    privacy_policy_version = case
      when profile.privacy_accepted_at is null
        then active_privacy_policy_version
      else profile.privacy_policy_version
    end;

  return query
  select profile.*
  from public.profiles profile
  where profile.id = current_user_id;
end;
$$;

comment on column public.profiles.terms_version is
  'Server-owned version of the terms accepted at terms_accepted_at.';
comment on column public.profiles.privacy_policy_version is
  'Server-owned version of the privacy policy accepted at privacy_accepted_at.';
