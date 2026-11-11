begin;

do $$
declare role_name text; helper record; relation text;
begin
    if exists(select 1 from pg_roles where rolname='yap_recommendation_exporter'
        and (rolcanlogin or rolsuper or rolcreaterole or rolcreatedb or rolreplication or rolbypassrls))
        then raise exception 'Dataset role is not restricted'; end if;
    foreach relation in array array['recsys_dataset.cohorts','recsys_dataset.members'] loop
        if not(select relrowsecurity from pg_class where oid=relation::regclass)
            then raise exception 'Dataset provenance table is missing RLS'; end if;
    end loop;
    foreach role_name in array array['anon','authenticated','service_role','yap_recommendation_worker','yap_feed_media_worker'] loop
        if has_schema_privilege(role_name,'recsys_dataset','USAGE')
            then raise exception 'Dataset schema exposed to %',role_name; end if;
        for helper in select p.oid,p.proname from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace where n.nspname='recsys_dataset'
        loop
            if has_function_privilege(role_name,helper.oid,'EXECUTE')
                then raise exception 'Dataset helper % exposed to %',helper.proname,role_name; end if;
        end loop;
    end loop;
    foreach relation in array array['recsys.feedback_facts','feed.posts','recsys_dataset.cohorts','recsys_dataset.members'] loop
        if has_table_privilege('yap_recommendation_exporter',relation,'SELECT,INSERT,UPDATE,DELETE')
            then raise exception 'Exporter can access raw table %',relation; end if;
    end loop;
    for helper in select p.oid,p.proname,p.prosecdef from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace where n.nspname='recsys_dataset'
    loop
        if has_function_privilege('yap_recommendation_exporter',helper.oid,'EXECUTE')
            <> (helper.proname in ('capture_info','capture_page'))
            or helper.prosecdef <> (helper.proname in ('capture_info','capture_page'))
            then raise exception 'Unexpected dataset function privilege: %',helper.proname; end if;
    end loop;
    if not exists(select 1 from pg_indexes where schemaname='recsys'
        and indexname='feedback_facts_dataset_seek_idx'
        and indexdef like '%(user_id, sequence)%')
        then raise exception 'Dataset capture is missing a bounded per-member seek'; end if;
end $$;

rollback;
