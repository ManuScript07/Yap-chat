-- Local Supabase only. Every fixture and counter change rolls back.
begin;
truncate private.yandex_userinfo_token_quota;
update private.yandex_userinfo_quota set window_started_at=clock_timestamp(),
  request_count=0, global_limit=6, token_limit=2, max_token_keys=6000;

do $$
declare r jsonb; before_count integer;
begin
  if has_function_privilege('anon','public.consume_yandex_userinfo_quota(text)','execute')
    or has_function_privilege('authenticated','public.consume_yandex_userinfo_quota(text)','execute')
    or has_function_privilege('anon','private.consume_yandex_userinfo_quota_impl(text)','execute')
    or has_function_privilege('authenticated','private.consume_yandex_userinfo_quota_impl(text)','execute')
    or has_table_privilege('service_role','private.yandex_userinfo_quota','update')
    or has_table_privilege('authenticated','private.yandex_userinfo_token_quota','select')
    or has_function_privilege('service_role','private.cleanup_yandex_userinfo_quota()','execute') then
    raise exception 'Quota privileges leaked';
  end if;
  if (select prosecdef from pg_proc where oid='public.consume_yandex_userinfo_quota(text)'::regprocedure) then
    raise exception 'Public quota bridge must be invoker';
  end if;
  begin
    perform public.consume_yandex_userinfo_quota('raw-token');
    raise exception 'Invalid fingerprint accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.consume_yandex_userinfo_quota(null);
    raise exception 'NULL fingerprint accepted';
  exception when invalid_parameter_value then null; end;
  if (select request_count from private.yandex_userinfo_quota) <> 0 then
    raise exception 'Malformed input consumed quota';
  end if;
end;
$$;

set local role service_role;
do $$
declare r jsonb;
begin
  for i in 1..2 loop
    if not (public.consume_yandex_userinfo_quota(repeat('a',64))->>'allowed')::boolean then
      raise exception 'Normal service admission denied';
    end if;
  end loop;
  r:=public.consume_yandex_userinfo_quota(repeat('a',64));
  if (r->>'allowed')::boolean or (r->>'retry_after_seconds')::integer not between 1 and 60
    or r->>'scope' is distinct from 'token' then
    raise exception 'Token quota/retry failed';
  end if;
  for i in 1..4 loop
    if not (public.consume_yandex_userinfo_quota(lpad(i::text,64,'0'))->>'allowed')::boolean then
      raise exception 'Other tokens should not share individual quota';
    end if;
  end loop;
  r:=public.consume_yandex_userinfo_quota(repeat('b',64));
  if (r->>'allowed')::boolean or r->>'scope' is distinct from 'global' then
    raise exception 'Rotating tokens bypassed global quota';
  end if;
end;
$$;
reset role;

do $$ begin
  if (select count(*) from private.yandex_userinfo_token_quota) <> 5
    or (select request_count from private.yandex_userinfo_quota) <> 6
    or (select request_count from private.yandex_userinfo_token_quota where token_hash=repeat('a',64)) <> 2 then
    raise exception 'Denial mutated counters or created a new key';
  end if;
  update private.yandex_userinfo_quota set window_started_at=clock_timestamp()-interval '61 seconds';
  -- Global expiry must not reset an unexpired individual token.
  if (public.consume_yandex_userinfo_quota(repeat('a',64))->>'allowed')::boolean then
    raise exception 'Global rollover bypassed token quota';
  end if;
  update private.yandex_userinfo_token_quota set expires_at=clock_timestamp()-interval '1 second';
  if not (public.consume_yandex_userinfo_quota(repeat('a',64))->>'allowed')::boolean then
    raise exception 'Expired token/global windows failed to reset';
  end if;
  if (select count(*) from private.yandex_userinfo_token_quota) <> 1
    or (select request_count from private.yandex_userinfo_quota) <> 1 then
    raise exception 'Pruning or rollover accounting failed';
  end if;
  update private.yandex_userinfo_quota set global_limit=100, max_token_keys=1;
  if (public.consume_yandex_userinfo_quota(repeat('c',64))->>'allowed')::boolean then
    raise exception 'Key cardinality cap bypassed';
  end if;
  if not (public.consume_yandex_userinfo_quota(repeat('a',64))->>'allowed')::boolean then
    raise exception 'Cardinality cap blocked an existing key';
  end if;
  update private.yandex_userinfo_token_quota set expires_at=clock_timestamp()-interval '1 second';
  if not (public.consume_yandex_userinfo_quota(repeat('c',64))->>'allowed')::boolean then
    raise exception 'Expired keys did not free capacity';
  end if;
end; $$;

truncate private.yandex_userinfo_token_quota;
update private.yandex_userinfo_quota set max_token_keys=6000, request_count=0;
insert into private.yandex_userinfo_token_quota
select lpad(to_hex(i),64,'0'), clock_timestamp()-interval '1 minute',1
from generate_series(1,5100) i;
do $$
declare removed integer;
begin
  removed := private.cleanup_yandex_userinfo_quota();
  if removed <> 5000 or (select count(*) from private.yandex_userinfo_token_quota) <> 100 then
    raise exception 'Hourly cleanup is not bounded/completable';
  end if;
  removed := private.cleanup_yandex_userinfo_quota();
  if removed <> 100 then raise exception 'Cleanup could not finish the remainder'; end if;
end; $$;

set local role anon;
do $$ begin
  begin
    perform public.consume_yandex_userinfo_quota(repeat('a',64));
    raise exception 'anon RPC unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
set local role authenticated;
do $$ begin
  begin
    perform public.consume_yandex_userinfo_quota(repeat('a',64));
    raise exception 'authenticated RPC unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from private.yandex_userinfo_token_quota;
    raise exception 'Fingerprint table unexpectedly readable';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
rollback;
