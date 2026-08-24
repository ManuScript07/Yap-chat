create or replace function private.handle_new_auth_user_impl()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  raw_birth_date text := coalesce(
    metadata ->> 'birth_date',
    metadata ->> 'birthdate',
    metadata ->> 'birthday'
  );
  verified_phone text := coalesce(
    nullif(new.phone::text, ''),
    nullif(metadata ->> 'phone', ''),
    nullif(metadata ->> 'phone_number', '')
  );
  lookup_hash bytea := private.phone_lookup_hash(verified_phone);
begin
  if lookup_hash is not null then
    update public.profiles
    set phone_lookup_hash = null
    where phone_lookup_hash = lookup_hash
      and id <> new.id;
  end if;

  insert into public.profiles (
    id,
    display_name,
    birth_date,
    avatar_url,
    phone_lookup_hash
  )
  values (
    new.id,
    coalesce(
      nullif(metadata ->> 'name', ''),
      nullif(metadata ->> 'real_name', ''),
      nullif(metadata ->> 'display_name', ''),
      ''
    ),
    case
      when raw_birth_date ~ '^[1-9][0-9]{3}-[0-9]{2}-[0-9]{2}$'
        then raw_birth_date::date
      else null
    end,
    coalesce(
      nullif(metadata ->> 'avatar_url', ''),
      nullif(metadata ->> 'picture', '')
    ),
    lookup_hash
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create or replace function private.sync_auth_user_phone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  verified_phone text := coalesce(
    nullif(new.phone::text, ''),
    (
      select coalesce(
        nullif(identity.identity_data ->> 'phone', ''),
        nullif(identity.identity_data ->> 'phone_number', '')
      )
      from auth.identities identity
      where identity.user_id = new.id
        and identity.provider = 'custom:yandex'
      order by identity.last_sign_in_at desc nulls last
      limit 1
    )
  );
  lookup_hash bytea := private.phone_lookup_hash(verified_phone);
begin
  if lookup_hash is null then
    return new;
  end if;

  update public.profiles
  set phone_lookup_hash = null
  where phone_lookup_hash = lookup_hash
    and id <> new.id;

  update public.profiles
  set phone_lookup_hash = lookup_hash
  where id = new.id
    and phone_lookup_hash is distinct from lookup_hash;

  return new;
end;
$$;

revoke all on function private.sync_auth_user_phone()
from public, anon, authenticated;

drop trigger if exists on_auth_user_phone_updated on auth.users;

create trigger on_auth_user_phone_updated
after update of raw_user_meta_data, phone on auth.users
for each row execute function private.sync_auth_user_phone();

do $$
declare
  auth_user record;
  lookup_hash bytea;
begin
  for auth_user in
    select
      users.id,
      coalesce(
        nullif(users.phone::text, ''),
        (
          select coalesce(
            nullif(identity.identity_data ->> 'phone', ''),
            nullif(identity.identity_data ->> 'phone_number', '')
          )
          from auth.identities identity
          where identity.user_id = users.id
            and identity.provider = 'custom:yandex'
          order by identity.last_sign_in_at desc nulls last
          limit 1
        )
      ) as verified_phone
    from auth.users users
    order by users.updated_at, users.id
  loop
    lookup_hash := private.phone_lookup_hash(auth_user.verified_phone);

    if lookup_hash is null then
      continue;
    end if;

    update public.profiles
    set phone_lookup_hash = null
    where phone_lookup_hash = lookup_hash
      and id <> auth_user.id;

    update public.profiles
    set phone_lookup_hash = lookup_hash
    where id = auth_user.id
      and phone_lookup_hash is distinct from lookup_hash;
  end loop;
end;
$$;

comment on function private.sync_auth_user_phone() is
  'Synchronizes the keyed phone lookup hash from verified OAuth/Auth fields.';
