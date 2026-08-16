create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  display_name text not null default '',
  birth_date date,
  avatar_url text,
  onboarding_completed boolean not null default false,
  terms_accepted_at timestamptz,
  privacy_accepted_at timestamptz,
  terms_version text not null default 'draft-v1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (
    username ~ '^[a-z0-9_]{3,24}$'
  ),
  constraint profiles_display_name_length check (
    char_length(display_name) <= 80
  ),
  constraint profiles_birth_date_range check (
    birth_date is null or (birth_date >= date '1900-01-01' and birth_date <= current_date)
  )
);

create or replace function public.generate_unique_username()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'abcdefghijklmnopqrstuvwxyz0123456789';
  candidate text;
begin
  loop
    select string_agg(
      substr(alphabet, floor(random() * length(alphabet) + 1)::integer, 1),
      ''
    )
    into candidate
    from generate_series(1, 8);

    exit when not exists (
      select 1
      from public.profiles
      where lower(username) = candidate
    );
  end loop;

  return candidate;
end;
$$;

alter table public.profiles
  alter column username set default public.generate_unique_username(),
  alter column username set not null;

create unique index profiles_username_lower_unique
on public.profiles (lower(username));

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
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
begin
  insert into public.profiles (
    id,
    display_name,
    birth_date,
    avatar_url
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
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

create policy "Users can create their own profile"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = id);

create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

grant select, insert, update on public.profiles to authenticated;
