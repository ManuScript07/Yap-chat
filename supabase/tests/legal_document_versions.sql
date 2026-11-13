begin;

insert into private.app_public_content (
  singleton,
  support_email,
  terms_version,
  privacy_policy_version
)
values (
  true,
  'support@example.com',
  'terms-of-use-v7',
  'privacy-policy-v9'
)
on conflict (singleton) do update
set terms_version = excluded.terms_version,
    privacy_policy_version = excluded.privacy_policy_version,
    updated_at = statement_timestamp();

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values (
  '50000000-0000-0000-0000-000000000001',
  false,
  false,
  '{"name":"Legal acceptance fixture"}'::jsonb
);

-- The auth trigger creates the profile before the welcome consent is recorded.
do $$
begin
  if exists (
    select 1
    from public.profiles profile
    where profile.id = '50000000-0000-0000-0000-000000000001'
      and (
        profile.terms_accepted_at is not null
        or profile.terms_version is not null
        or profile.privacy_accepted_at is not null
        or profile.privacy_policy_version is not null
      )
  ) then
    raise exception 'Auth trigger must not fabricate legal acceptance';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '50000000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select * from public.get_or_create_my_profile('Legal acceptance fixture', null, null);
reset role;

do $$
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = '50000000-0000-0000-0000-000000000001'
      and profile.terms_accepted_at is not null
      and profile.terms_version = 'terms-of-use-v7'
      and profile.privacy_accepted_at is not null
      and profile.privacy_policy_version = 'privacy-policy-v9'
  ) then
    raise exception 'Profile did not retain active legal document versions';
  end if;
end;
$$;

-- Later document publication must not rewrite historic consent.
update private.app_public_content
set terms_version = 'terms-of-use-v8',
    privacy_policy_version = 'privacy-policy-v10';

select set_config(
  'request.jwt.claim.sub',
  '50000000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select * from public.get_or_create_my_profile(null, null, null);
reset role;

do $$
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = '50000000-0000-0000-0000-000000000001'
      and profile.terms_version = 'terms-of-use-v7'
      and profile.privacy_policy_version = 'privacy-policy-v9'
  ) then
    raise exception 'A later legal document version rewrote historic consent';
  end if;
end;
$$;

rollback;
