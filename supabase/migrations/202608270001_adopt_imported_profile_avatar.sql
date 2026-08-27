create or replace function public.adopt_imported_profile_avatar(
  p_storage_path text,
  p_updated_at timestamptz default now()
)
returns setof public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_path text := btrim(p_storage_path);
  effective_updated_at timestamptz := coalesce(p_updated_at, now());
begin
  if current_user_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if normalized_path = '' or
      split_part(normalized_path, '/', 1) <> current_user_id::text then
    raise exception 'Invalid profile avatar path' using errcode = '22023';
  end if;

  update public.profiles
  set
    avatar_url = null,
    avatar_storage_path = normalized_path,
    avatar_updated_at = effective_updated_at
  where id = current_user_id;

  if not found then
    raise exception 'Profile was not found' using errcode = 'P0002';
  end if;

  insert into public.profile_photos (
    profile_id,
    position,
    avatar_url,
    storage_path,
    updated_at
  ) values (
    current_user_id,
    0,
    null,
    normalized_path,
    effective_updated_at
  )
  on conflict (profile_id, position) do update
  set
    avatar_url = excluded.avatar_url,
    storage_path = excluded.storage_path,
    updated_at = excluded.updated_at;

  return query
  select profile.*
  from public.profiles profile
  where profile.id = current_user_id;
end;
$$;

revoke all on function public.adopt_imported_profile_avatar(
  text,
  timestamptz
) from public, anon;

grant execute on function public.adopt_imported_profile_avatar(
  text,
  timestamptz
) to authenticated;

comment on function public.adopt_imported_profile_avatar(
  text,
  timestamptz
) is 'Atomically adopts an imported external avatar for the current profile.';
