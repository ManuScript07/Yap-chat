-- Privacy writes are intentionally narrow: one client action changes one
-- server field, so a stale device cannot restore unrelated settings.
create table private.search_privacy_settings_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0)
);

revoke all on table private.search_privacy_settings_write_limits
from public, anon, authenticated;

create or replace function private.consume_search_privacy_settings_write_quota()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  was_accepted boolean;
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  -- The conflict row is locked by PostgreSQL. This makes the 20/minute limit
  -- apply even to concurrent calls made outside the Flutter client.
  insert into private.search_privacy_settings_write_limits as limits (
    user_id,
    window_started_at,
    request_count
  ) values (
    auth.uid(),
    now(),
    1
  )
  on conflict (user_id) do update
  set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  where limits.window_started_at <= now() - interval '1 minute'
     or limits.request_count < 20
  returning true into was_accepted;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'search_privacy_settings_rate_limited';
  end if;
end;
$$;

revoke all on function private.consume_search_privacy_settings_write_quota()
from public, anon;
grant execute on function private.consume_search_privacy_settings_write_quota()
to authenticated, service_role;

-- Preserve the old endpoint for already released clients, but make it obey
-- the same server-side quota.
create or replace function private.update_my_search_privacy_settings_impl(
  is_searchable_by_username boolean,
  is_searchable_by_phone boolean,
  is_searchable_by_name boolean
)
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  perform private.consume_search_privacy_settings_write_quota();

  return query
  insert into private.search_privacy_settings as settings (
    user_id,
    search_by_username,
    search_by_phone,
    search_by_name,
    updated_at
  ) values (
    auth.uid(),
    is_searchable_by_username,
    is_searchable_by_phone,
    is_searchable_by_name,
    now()
  )
  on conflict (user_id) do update
  set
    search_by_username = excluded.search_by_username,
    search_by_phone = excluded.search_by_phone,
    search_by_name = excluded.search_by_name,
    updated_at = excluded.updated_at
  returning
    settings.search_by_username,
    settings.search_by_phone,
    settings.search_by_name;
end;
$$;

create or replace function private.set_my_search_privacy_setting_impl(
  setting_key text,
  is_enabled boolean
)
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;
  if setting_key not in ('username', 'phone', 'name') or is_enabled is null then
    raise exception using
      errcode = '22023',
      message = 'invalid_search_privacy_setting';
  end if;

  perform private.consume_search_privacy_settings_write_quota();

  return query
  insert into private.search_privacy_settings as settings (
    user_id,
    search_by_username,
    search_by_phone,
    search_by_name,
    updated_at
  ) values (
    auth.uid(),
    case when setting_key = 'username' then is_enabled else true end,
    case when setting_key = 'phone' then is_enabled else true end,
    case when setting_key = 'name' then is_enabled else true end,
    now()
  )
  on conflict (user_id) do update
  set
    search_by_username = case
      when setting_key = 'username' then is_enabled
      else settings.search_by_username
    end,
    search_by_phone = case
      when setting_key = 'phone' then is_enabled
      else settings.search_by_phone
    end,
    search_by_name = case
      when setting_key = 'name' then is_enabled
      else settings.search_by_name
    end,
    updated_at = now()
  returning
    settings.search_by_username,
    settings.search_by_phone,
    settings.search_by_name;
end;
$$;

revoke all on function private.set_my_search_privacy_setting_impl(text, boolean)
from public, anon;
grant execute on function private.set_my_search_privacy_setting_impl(text, boolean)
to authenticated, service_role;

create or replace function public.set_my_search_privacy_setting(
  setting_key text,
  is_enabled boolean
)
returns table (
  search_by_username boolean,
  search_by_phone boolean,
  search_by_name boolean
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.set_my_search_privacy_setting_impl(
    setting_key,
    is_enabled
  );
$$;

revoke all on function public.set_my_search_privacy_setting(text, boolean)
from public, anon;
grant execute on function public.set_my_search_privacy_setting(text, boolean)
to authenticated, service_role;

-- A single setting now governs telephone discovery. Existing friends remain
-- visible, but the former unused profile flag no longer creates a hidden
-- second source of truth.
create or replace function private.match_contact_phones_impl(phone_numbers text[])
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
   and profile.onboarding_completed
   and profile.id <> viewer.id
  left join private.search_privacy_settings privacy
    on privacy.user_id = profile.id
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, viewer.id)
   and friendship.user_two_id = greatest(profile.id, viewer.id)
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, viewer.id)
   and request.pair_user_two_id = greatest(profile.id, viewer.id)
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where viewer.id is not null
    and (
      coalesce(privacy.search_by_phone, true)
      or friendship.id is not null
    )
  order by input.position;
$$;

revoke all on function private.match_contact_phones_impl(text[])
from public, anon;
grant execute on function private.match_contact_phones_impl(text[])
to authenticated, service_role;
