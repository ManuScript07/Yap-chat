-- Pre-session admission is keyed by HMAC(provider token), never auth.uid/IP.
create table private.yandex_userinfo_quota (
  singleton boolean primary key default true check (singleton),
  window_started_at timestamptz not null default clock_timestamp(),
  request_count integer not null default 0 check (request_count >= 0),
  global_limit integer not null default 600 check (global_limit between 1 and 10000),
  token_limit integer not null default 10 check (token_limit between 1 and 1000),
  max_token_keys integer not null default 6000 check (max_token_keys between 1 and 100000)
);
insert into private.yandex_userinfo_quota (singleton) values (true);
create table private.yandex_userinfo_token_quota (
  token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  request_count integer not null check (request_count > 0)
);
create index yandex_userinfo_token_quota_expires_idx
  on private.yandex_userinfo_token_quota (expires_at);
alter table private.yandex_userinfo_quota enable row level security;
alter table private.yandex_userinfo_token_quota enable row level security;
revoke all on private.yandex_userinfo_quota, private.yandex_userinfo_token_quota
  from public, anon, authenticated, service_role;

create function private.consume_yandex_userinfo_quota_impl(token_hash text)
returns jsonb language plpgsql security definer set search_path = ''
set lock_timeout = '250ms'
as $$
declare
  quota private.yandex_userinfo_quota%rowtype;
  token_quota private.yandex_userinfo_token_quota%rowtype;
  at_time timestamptz;
  retry_seconds integer;
begin
  if token_hash is null or token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_token_fingerprint';
  end if;
  -- Always acquire locks in this order; denial does not update counter rows.
  select * into strict quota from private.yandex_userinfo_quota
    where singleton for update;
  at_time := clock_timestamp();
  if quota.window_started_at <= at_time - interval '1 minute' then
    quota.window_started_at := at_time;
    quota.request_count := 0;
  end if;
  retry_seconds := greatest(1, least(60, ceil(extract(epoch from
    quota.window_started_at + interval '1 minute' - at_time))::integer));
  if quota.request_count >= quota.global_limit then
    return jsonb_build_object('allowed', false, 'retry_after_seconds', retry_seconds, 'scope', 'global');
  end if;

  select * into token_quota from private.yandex_userinfo_token_quota t
    where t.token_hash = consume_yandex_userinfo_quota_impl.token_hash;
  if found and token_quota.expires_at > at_time then
    if token_quota.request_count >= quota.token_limit then
      return jsonb_build_object('allowed', false, 'scope', 'token', 'retry_after_seconds',
        greatest(1, least(60, ceil(extract(epoch from token_quota.expires_at - at_time))::integer)));
    end if;
    update private.yandex_userinfo_token_quota t
      set request_count = t.request_count + 1
      where t.token_hash = consume_yandex_userinfo_quota_impl.token_hash;
  else
    -- Indexed, bounded pruning, only on creation/reset of a token key.
    delete from private.yandex_userinfo_token_quota old where old.token_hash in (
      select t.token_hash from private.yandex_userinfo_token_quota t
      where expires_at <= at_time order by expires_at limit 32
    );
    if token_quota.token_hash is null and
      (select count(*) from private.yandex_userinfo_token_quota) >= quota.max_token_keys then
      return jsonb_build_object('allowed', false, 'retry_after_seconds', 60, 'scope', 'token');
    end if;
    insert into private.yandex_userinfo_token_quota (token_hash, expires_at, request_count)
      values (consume_yandex_userinfo_quota_impl.token_hash, at_time + interval '1 minute', 1)
      on conflict on constraint yandex_userinfo_token_quota_pkey do update
      set expires_at = excluded.expires_at, request_count = 1;
  end if;
  update private.yandex_userinfo_quota
    set window_started_at = quota.window_started_at, request_count = quota.request_count + 1
    where singleton;
  -- A normal result commits admission even if Yandex subsequently rejects it.
  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end;
$$;
revoke all on function private.consume_yandex_userinfo_quota_impl(text)
  from public, anon, authenticated;
grant execute on function private.consume_yandex_userinfo_quota_impl(text) to service_role;

create function public.consume_yandex_userinfo_quota(token_hash text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.consume_yandex_userinfo_quota_impl(token_hash); $$;
revoke all on function public.consume_yandex_userinfo_quota(text)
  from public, anon, authenticated;
grant execute on function public.consume_yandex_userinfo_quota(text) to service_role;

-- Idle cleanup never calls an Edge Function or external API.
create function private.cleanup_yandex_userinfo_quota()
returns integer language plpgsql security definer set search_path = ''
set lock_timeout = '250ms'
as $$
declare removed integer;
begin
  perform 1 from private.yandex_userinfo_quota where singleton for update;
  delete from private.yandex_userinfo_token_quota where token_hash in (
    select token_hash from private.yandex_userinfo_token_quota
    where expires_at <= clock_timestamp() order by expires_at limit 5000
  );
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function private.cleanup_yandex_userinfo_quota()
  from public, anon, authenticated, service_role;
do $$ begin
  if to_regclass('cron.job') is not null then
    perform cron.schedule('cleanup-yandex-userinfo-quota', '23 * * * *',
      'select private.cleanup_yandex_userinfo_quota()');
  end if;
end; $$;
notify pgrst, 'reload schema';
