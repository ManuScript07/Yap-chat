create extension if not exists pgcrypto with schema extensions;

create table private.phone_lookup_secrets (
  singleton boolean primary key default true check (singleton),
  secret bytea not null
);

revoke all on table private.phone_lookup_secrets
from public, anon, authenticated;

insert into private.phone_lookup_secrets (singleton, secret)
values (true, extensions.gen_random_bytes(32));

create function private.normalize_phone(raw_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when regexp_replace(coalesce(raw_phone, ''), '[^0-9+]', '', 'g')
      ~ '^\+[1-9][0-9]{7,14}$'
      then regexp_replace(raw_phone, '[^0-9+]', '', 'g')
    else null
  end;
$$;

create function private.phone_lookup_hash(raw_phone text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.hmac(
    pg_catalog.convert_to(private.normalize_phone(raw_phone), 'UTF8'),
    secret.secret,
    'sha256'
  )
  from private.phone_lookup_secrets secret
  where secret.singleton
    and private.normalize_phone(raw_phone) is not null;
$$;

revoke all on function private.normalize_phone(text)
from public, anon, authenticated;
revoke all on function private.phone_lookup_hash(text)
from public, anon, authenticated;

alter table public.profiles
add column phone_lookup_hash bytea,
add column discoverable_by_phone boolean not null default true;

create unique index profiles_phone_lookup_hash_unique
on public.profiles (phone_lookup_hash)
where phone_lookup_hash is not null;

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
    metadata ->> 'birthday'
  );
  verified_phone text := coalesce(
    nullif(metadata ->> 'phone_number', ''),
    nullif(metadata ->> 'phone', '')
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

create function private.sync_auth_user_phone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  verified_phone text := coalesce(
    nullif(metadata ->> 'phone_number', ''),
    nullif(metadata ->> 'phone', '')
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
  where id = new.id;

  return new;
end;
$$;

revoke all on function private.sync_auth_user_phone()
from public, anon, authenticated;

create trigger on_auth_user_phone_updated
after update of raw_user_meta_data on auth.users
for each row execute function private.sync_auth_user_phone();

create function private.match_contact_phones_impl(phone_numbers text[])
returns table (
  phone_number text,
  id uuid,
  request_id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security definer
set search_path = ''
as $$
  with viewer as materialized (
    select auth.uid() as id
  ),
  normalized_input as (
    select normalized.phone_number, min(source.position) as position
    from unnest(coalesce(phone_numbers, array[]::text[]))
      with ordinality as source(phone_number, position)
    cross join lateral (
      select private.normalize_phone(source.phone_number) as phone_number
    ) normalized
    where normalized.phone_number is not null
    group by normalized.phone_number
    order by min(source.position)
    limit 500
  ),
  input as materialized (
    select
      normalized_input.phone_number,
      normalized_input.position,
      private.phone_lookup_hash(normalized_input.phone_number) as lookup_hash
    from normalized_input
  )
  select
    input.phone_number,
    profile.id,
    request.id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when profile.show_friends_count
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    case
      when friendship.id is not null then 'friend'
      when request.sender_id = viewer.id then 'outgoing'
      when request.recipient_id = viewer.id then 'incoming'
      else 'none'
    end
  from input
  cross join viewer
  join public.profiles profile
    on profile.phone_lookup_hash = input.lookup_hash
   and profile.discoverable_by_phone
   and profile.onboarding_completed
   and profile.id <> viewer.id
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, viewer.id)
   and friendship.user_two_id = greatest(profile.id, viewer.id)
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, viewer.id)
   and request.pair_user_two_id = greatest(profile.id, viewer.id)
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where viewer.id is not null
  order by input.position;
$$;

revoke all on function private.match_contact_phones_impl(text[])
from public, anon;
grant execute on function private.match_contact_phones_impl(text[])
to authenticated, service_role;

create function public.match_contact_phones(phone_numbers text[])
returns table (
  phone_number text,
  id uuid,
  request_id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.match_contact_phones_impl(phone_numbers);
$$;

revoke all on function public.match_contact_phones(text[])
from public, anon;
grant execute on function public.match_contact_phones(text[])
to authenticated, service_role;

create function private.set_phone_discoverability_impl(is_discoverable boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  update public.profiles
  set discoverable_by_phone = is_discoverable
  where id = auth.uid();
end;
$$;

revoke all on function private.set_phone_discoverability_impl(boolean)
from public, anon;
grant execute on function private.set_phone_discoverability_impl(boolean)
to authenticated, service_role;

create function public.set_phone_discoverability(is_discoverable boolean)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_phone_discoverability_impl(is_discoverable);
$$;

revoke all on function public.set_phone_discoverability(boolean)
from public, anon;
grant execute on function public.set_phone_discoverability(boolean)
to authenticated, service_role;

comment on column public.profiles.phone_lookup_hash is
  'Server-keyed HMAC of the verified Yandex phone; the raw number is not stored.';
comment on column public.profiles.discoverable_by_phone is
  'Future UI privacy switch for exact contact and phone-number discovery.';
