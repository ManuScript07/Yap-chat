-- Public, non-sensitive application links are maintained in one private
-- singleton. Clients receive them only through the narrow RPC below; no table
-- access is exposed to anon or authenticated roles.
create table private.app_public_content (
  singleton boolean primary key default true check (singleton),
  support_email text,
  terms_url_ru text,
  terms_url_en text,
  privacy_policy_url_ru text,
  privacy_policy_url_en text,
  telegram_url text,
  updated_at timestamptz not null default now(),
  check (support_email is null or support_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  check (terms_url_ru is null or terms_url_ru ~* '^https://'),
  check (terms_url_en is null or terms_url_en ~* '^https://'),
  check (privacy_policy_url_ru is null or privacy_policy_url_ru ~* '^https://'),
  check (privacy_policy_url_en is null or privacy_policy_url_en ~* '^https://'),
  check (telegram_url is null or telegram_url ~* '^https://')
);

revoke all on table private.app_public_content from public, anon, authenticated;

create function private.get_public_app_content_impl()
returns table (
  support_email text,
  terms_url_ru text,
  terms_url_en text,
  privacy_policy_url_ru text,
  privacy_policy_url_en text,
  telegram_url text,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select content.support_email,
         content.terms_url_ru,
         content.terms_url_en,
         content.privacy_policy_url_ru,
         content.privacy_policy_url_en,
         content.telegram_url,
         content.updated_at
  from private.app_public_content content
  where content.singleton;
$$;

create function public.get_public_app_content()
returns table (
  support_email text,
  terms_url_ru text,
  terms_url_en text,
  privacy_policy_url_ru text,
  privacy_policy_url_en text,
  telegram_url text,
  updated_at timestamptz
)
language sql security definer set search_path = ''
as $$ select * from private.get_public_app_content_impl(); $$;

revoke all on function private.get_public_app_content_impl() from public, anon;
grant execute on function private.get_public_app_content_impl() to authenticated, service_role;
grant execute on function public.get_public_app_content() to anon, authenticated, service_role;

-- Upload the versioned PDFs to the public `legal-documents` bucket, then add
-- the active URLs and contact information here. No value is intentionally
-- invented by this migration.
--
-- insert into private.app_public_content (
--   support_email, terms_url_ru, terms_url_en, privacy_policy_url_ru,
--   privacy_policy_url_en, telegram_url
-- ) values (...)
-- on conflict (singleton) do update set ... , updated_at = now();
