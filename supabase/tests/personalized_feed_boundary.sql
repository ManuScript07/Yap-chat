begin;

do $$ declare r record; role_name text; signature text; begin
  for r in select c.oid,n.nspname,c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('feed','recsys')and c.relkind='r'loop
    if not r.relrowsecurity then raise exception 'RLS disabled on %.%',r.nspname,r.relname;end if;
    foreach role_name in array array['anon','authenticated','yap_recommendation_worker']loop
      if has_table_privilege(role_name,r.oid,'SELECT,INSERT,UPDATE,DELETE')then
        raise exception 'Raw access granted to % on %.%',role_name,r.nspname,r.relname;
      end if;
    end loop;
  end loop;
  foreach signature in array array[
    'get_for_you_feed(uuid,integer,integer)','record_feed_events(jsonb)','apply_feed_action(uuid,uuid,text,bigint)',
    'set_recommendation_author_hidden(uuid,uuid,boolean)','reset_recommendation_interests(uuid)',
    'get_recommendation_hidden_authors(uuid,integer)'
  ]loop
    if not has_function_privilege('authenticated','public.'||signature,'EXECUTE')
      or has_function_privilege('anon','public.'||signature,'EXECUTE')
      or has_function_privilege('yap_recommendation_worker','public.'||signature,'EXECUTE') then
      raise exception 'Invalid public RPC grants: %',signature;
    end if;
    if (select prosecdef from pg_proc where oid=('public.'||signature)::regprocedure)then
      raise exception 'Public wrapper is security definer: %',signature;
    end if;
  end loop;
  for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='recsys'loop
    if has_function_privilege('anon',r.oid,'EXECUTE')or has_function_privilege('authenticated',r.oid,'EXECUTE')then
      raise exception 'Internal function exposed: %',r.proname;
    end if;
  end loop;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
  begin perform public.get_for_you_feed();raise exception 'Anonymous identity accepted';
  exception when insufficient_privilege then null;end;
end $$;
reset role;

rollback;
