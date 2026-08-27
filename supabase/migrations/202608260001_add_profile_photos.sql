create table public.profile_photos (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  position smallint not null,
  avatar_url text,
  storage_path text,
  updated_at timestamptz not null default now(),
  primary key (profile_id, position),
  constraint profile_photos_position_range check (position between 0 and 4),
  constraint profile_photos_single_source check (
    (avatar_url is null) <> (storage_path is null)
  )
);

insert into public.profile_photos (
  profile_id,
  position,
  avatar_url,
  storage_path,
  updated_at
)
select
  profile.id,
  0,
  case when profile.avatar_storage_path is null then profile.avatar_url end,
  profile.avatar_storage_path,
  coalesce(profile.avatar_updated_at, profile.updated_at, now())
from public.profiles profile
where profile.avatar_url is not null or profile.avatar_storage_path is not null
on conflict (profile_id, position) do nothing;

alter table public.profile_photos enable row level security;

create policy "Users can view their own profile photos"
on public.profile_photos
for select
to authenticated
using ((select auth.uid()) = profile_id);

create policy "Users can create their own profile photos"
on public.profile_photos
for insert
to authenticated
with check ((select auth.uid()) = profile_id);

create policy "Users can update their own profile photos"
on public.profile_photos
for update
to authenticated
using ((select auth.uid()) = profile_id)
with check ((select auth.uid()) = profile_id);

create policy "Users can delete their own profile photos"
on public.profile_photos
for delete
to authenticated
using ((select auth.uid()) = profile_id);

grant select, insert, update, delete on public.profile_photos to authenticated;

create or replace function public.save_own_profile(
  p_display_name text,
  p_birth_date date,
  p_gender text,
  p_username text,
  p_bio text,
  p_photos jsonb
)
returns setof public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_photos jsonb := coalesce(p_photos, '[]'::jsonb);
  photo_count integer;
  first_photo jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if jsonb_typeof(normalized_photos) <> 'array' then
    raise exception 'Photos must be a JSON array' using errcode = '22023';
  end if;

  photo_count := jsonb_array_length(normalized_photos);
  if photo_count > 5 then
    raise exception 'A profile can contain at most five photos'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(normalized_photos) photo
    where
      (nullif(photo ->> 'avatar_url', '') is null) =
        (nullif(photo ->> 'storage_path', '') is null)
      or (
        nullif(photo ->> 'storage_path', '') is not null
        and split_part(photo ->> 'storage_path', '/', 1) <> current_user_id::text
      )
  ) then
    raise exception 'Invalid profile photo source' using errcode = '22023';
  end if;

  first_photo := normalized_photos -> 0;

  update public.profiles
  set
    display_name = btrim(p_display_name),
    birth_date = p_birth_date,
    gender = p_gender,
    username = lower(btrim(p_username)),
    bio = btrim(coalesce(p_bio, '')),
    onboarding_completed = true,
    avatar_url = nullif(first_photo ->> 'avatar_url', ''),
    avatar_storage_path = nullif(first_photo ->> 'storage_path', ''),
    avatar_updated_at = case
      when first_photo is null then null
      else coalesce(
        nullif(first_photo ->> 'updated_at', '')::timestamptz,
        now()
      )
    end
  where id = current_user_id;

  if not found then
    raise exception 'Profile was not found' using errcode = 'P0002';
  end if;

  delete from public.profile_photos where profile_id = current_user_id;

  insert into public.profile_photos (
    profile_id,
    position,
    avatar_url,
    storage_path,
    updated_at
  )
  select
    current_user_id,
    (item.ordinality - 1)::smallint,
    nullif(item.photo ->> 'avatar_url', ''),
    nullif(item.photo ->> 'storage_path', ''),
    coalesce(
      nullif(item.photo ->> 'updated_at', '')::timestamptz,
      now()
    )
  from jsonb_array_elements(normalized_photos)
    with ordinality as item(photo, ordinality);

  return query
  select profile.*
  from public.profiles profile
  where profile.id = current_user_id;
end;
$$;

revoke all on function public.save_own_profile(
  text,
  date,
  text,
  text,
  text,
  jsonb
) from public, anon;

grant execute on function public.save_own_profile(
  text,
  date,
  text,
  text,
  text,
  jsonb
) to authenticated;

comment on function public.save_own_profile(
  text,
  date,
  text,
  text,
  text,
  jsonb
) is 'Atomically saves the current profile and its ordered photo list.';
