-- A missing avatar has two distinct meanings: it can be a new profile that
-- has not yet imported Yandex data, or an explicit decision by its owner to
-- remove every photo. Keep that decision permanently, so an auth refresh can
-- never restore an external avatar without a new user action.
alter table public.profiles
  add column if not exists yandex_avatar_disabled boolean not null default false;

-- Existing completed profiles with no photo must be treated conservatively:
-- restoring an OAuth-provider image for them would be a privacy regression.
update public.profiles profile
set yandex_avatar_disabled = true
where profile.onboarding_completed
  and profile.avatar_url is null
  and profile.avatar_storage_path is null
  and not exists (
    select 1
    from public.profile_photos photo
    where photo.profile_id = profile.id
  );

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
    -- Once the user has removed every photo, only an explicit new photo may
    -- appear again; OAuth metadata must not be used as a fallback.
    yandex_avatar_disabled = case
      when photo_count = 0 then true
      else yandex_avatar_disabled
    end,
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
