-- Account preferences are intentionally separate from privacy settings. The
-- absence of a row preserves the device language used by existing accounts.
create table private.account_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  app_language text not null check (app_language in ('ru', 'en')),
  updated_at timestamptz not null default now()
);

revoke all on table private.account_settings from public, anon, authenticated;

-- The language picker makes one write per explicit selection. A small server
-- quota protects this endpoint even if a modified client ignores its local
-- in-flight guard.
create table private.account_settings_write_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count > 0)
);

revoke all on table private.account_settings_write_limits from public, anon, authenticated;

create function private.consume_app_settings_write_quota()
returns void language plpgsql security definer set search_path = ''
as $$
declare current_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  insert into private.account_settings_write_limits as limits (
    user_id, window_started_at, request_count
  ) values (auth.uid(), now(), 1)
  on conflict on constraint account_settings_write_limits_pkey do update set
    window_started_at = case
      when limits.window_started_at <= now() - interval '1 minute' then now()
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= now() - interval '1 minute' then 1
      else limits.request_count + 1
    end
  returning request_count into current_count;
  if current_count > 10 then
    raise exception using errcode = 'P0001', message = 'app_settings_rate_limited';
  end if;
end;
$$;

create function private.get_my_app_language_impl()
returns table (language_code text)
language sql stable security definer set search_path = ''
as $$
  select settings.app_language
  from private.account_settings settings
  where settings.user_id = auth.uid();
$$;

-- `register_push_device` intentionally stays security invoker. It therefore
-- obtains the private preference through this narrow, authenticated helper
-- instead of receiving direct access to the private table.
create function private.get_current_app_language_for_push_impl()
returns text
language sql stable security definer set search_path = ''
as $$
  select settings.app_language
  from private.account_settings settings
  where settings.user_id = auth.uid();
$$;

create function private.set_my_app_language_impl(requested_language_code text)
returns table (language_code text)
language plpgsql security definer set search_path = ''
as $$
declare normalized_language text := lower(trim(coalesce(requested_language_code, '')));
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if normalized_language not in ('ru', 'en') then
    raise exception using errcode = '22023', message = 'invalid_app_language';
  end if;
  perform private.consume_app_settings_write_quota();
  insert into private.account_settings as settings (user_id, app_language, updated_at)
  values (auth.uid(), normalized_language, now())
  on conflict (user_id) do update set
    app_language = excluded.app_language,
    updated_at = excluded.updated_at;

  -- Notifications are account-scoped too. Update all known devices now, so
  -- the change does not wait for an FCM token refresh.
  update public.push_devices device
  set locale = normalized_language, updated_at = now()
  where device.user_id = auth.uid();

  return query select normalized_language;
end;
$$;

create function public.get_my_app_language()
returns table (language_code text)
language sql security invoker set search_path = ''
as $$ select * from private.get_my_app_language_impl(); $$;

create function public.set_my_app_language(language_code text)
returns table (language_code text)
language sql security invoker set search_path = ''
as $$ select * from private.set_my_app_language_impl(language_code); $$;

revoke all on function private.consume_app_settings_write_quota() from public, anon;
revoke all on function private.get_my_app_language_impl() from public, anon;
revoke all on function private.get_current_app_language_for_push_impl() from public, anon;
revoke all on function private.set_my_app_language_impl(text) from public, anon;
grant execute on function private.consume_app_settings_write_quota() to authenticated, service_role;
grant execute on function private.get_my_app_language_impl() to authenticated, service_role;
grant execute on function private.get_current_app_language_for_push_impl() to authenticated, service_role;
grant execute on function private.set_my_app_language_impl(text) to authenticated, service_role;
grant execute on function public.get_my_app_language() to authenticated, service_role;
grant execute on function public.set_my_app_language(text) to authenticated, service_role;

-- A newly registered token must honor an already selected account language,
-- rather than silently reverting notifications to the OS language.
create or replace function public.register_push_device(
  device_token text,
  device_locale text default 'ru',
  device_app_version text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_token text := trim(device_token);
  saved_language text;
  normalized_locale text;
begin
  if current_user_id is null then
    raise exception 'authentication_required';
  end if;
  if length(normalized_token) not between 20 and 4096 then
    raise exception 'invalid_push_token';
  end if;

  select private.get_current_app_language_for_push_impl() into saved_language;
  normalized_locale := case
    when saved_language in ('ru', 'en') then saved_language
    when lower(trim(coalesce(device_locale, ''))) = 'en' then 'en'
    else 'ru'
  end;

  insert into public.push_devices (
    user_id, token, platform, locale, app_version, enabled, updated_at, last_seen_at
  ) values (
    current_user_id, normalized_token, 'android', normalized_locale,
    nullif(trim(coalesce(device_app_version, '')), ''), true, now(), now()
  ) on conflict (token) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    locale = excluded.locale,
    app_version = excluded.app_version,
    enabled = true,
    updated_at = now(),
    last_seen_at = now();

  delete from public.push_devices device
  where device.id in (
    select stale_device.id
    from public.push_devices stale_device
    where stale_device.user_id = current_user_id
    order by stale_device.last_seen_at desc, stale_device.id desc
    offset 10
  );
end;
$$;

grant execute on function public.register_push_device(text, text, text)
  to authenticated;
