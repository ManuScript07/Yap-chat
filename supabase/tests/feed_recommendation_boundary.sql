begin;

do $$
declare role_name text; table_name text;
begin
  if exists (select 1 from pg_roles where rolname='yap_recommendation_worker'
    and (rolsuper or rolcreatedb or rolcreaterole or rolbypassrls or rolcanlogin)) then
    raise exception 'Unsafe worker group role';
  end if;
  foreach role_name in array array['anon', 'authenticated', 'yap_recommendation_worker'] loop
    if has_schema_privilege(role_name, 'feed', 'USAGE') then
      raise exception 'Unexpected raw feed schema access for %', role_name;
    end if;
    foreach table_name in array array['feed.posts', 'recsys.index_jobs', 'recsys.post_embeddings'] loop
      if has_table_privilege(role_name, table_name, 'SELECT,INSERT,UPDATE,DELETE') then
        raise exception 'Unexpected raw table access for % on %', role_name, table_name;
      end if;
    end loop;
  end loop;
  if has_schema_privilege('authenticated', 'recsys', 'USAGE')
    or has_function_privilege('anon', 'public.create_feed_post(uuid,text,text,text)', 'EXECUTE')
    or has_function_privilege('yap_recommendation_worker', 'public.create_feed_post(uuid,text,text,text)', 'EXECUTE')
    or has_function_privilege('authenticated', 'recsys.claim_index_job(uuid,text)', 'EXECUTE') then
    raise exception 'Client/worker boundary is exposed';
  end if;
  if not has_function_privilege('authenticated', 'public.create_feed_post(uuid,text,text,text)', 'EXECUTE')
    or not has_function_privilege('yap_recommendation_worker', 'recsys.claim_index_job(uuid,text)', 'EXECUTE') then
    raise exception 'Required RPC boundary is missing';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('create_feed_post','edit_feed_post','delete_feed_post','get_feed_post')
      and p.prosecdef) then
    raise exception 'Public feed wrappers must be security invoker';
  end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('feed','recsys') and c.relkind='r' and not c.relrowsecurity) then
    raise exception 'Feed tables must enable RLS as defense in depth';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$ begin
  begin
    perform public.get_feed_post('00000000-0000-0000-0000-000000000000');
    raise exception 'Missing identity was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

rollback;
