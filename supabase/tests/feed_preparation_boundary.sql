begin;

do $$
declare role_name text; signature text; table_name text;
begin
    foreach table_name in array array['recsys.author_statistics','recsys.author_viewers'] loop
        if not(select relrowsecurity from pg_class where oid=table_name::regclass)then
            raise exception 'Author coverage missing RLS: %',table_name;end if;
        foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
            if has_table_privilege(role_name,table_name,'SELECT,INSERT,UPDATE,DELETE')then
                raise exception 'Raw author coverage exposed: % %',role_name,table_name;end if;
        end loop;
    end loop;
    foreach signature in array array[
        'recsys.claim_refresh_job(uuid,integer)','recsys.claim_index_batch(uuid,text,text,integer)',
        'recsys.complete_index_batch(jsonb)','recsys.enqueue_index_backfill(uuid,integer)',
        'recsys.preparation_queue_snapshot()'
    ]loop
        if not has_function_privilege('yap_recommendation_worker',signature,'EXECUTE')then
            raise exception 'Missing worker entry point: %',signature;end if;
        foreach role_name in array array['anon','authenticated','yap_feed_media_worker']loop
            if has_function_privilege(role_name,signature,'EXECUTE')then
                raise exception 'Worker entry point exposed: % %',role_name,signature;end if;
        end loop;
    end loop;
    foreach signature in array array[
        'private.create_author_statistics()','private.record_author_reach(uuid,uuid)',
        'private.stamp_feed_delivery_versions()','private.feed_geo_distance(double precision,double precision,double precision,double precision)',
        'private.feed_geo_longitude_delta(double precision,double precision)'
    ]loop
        foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
            if has_function_privilege(role_name,signature,'EXECUTE')then
                raise exception 'Private helper exposed: % %',role_name,signature;end if;
        end loop;
    end loop;
    signature:='public.get_nearby_feed(uuid,integer,integer,integer)';
    if (select prosecdef from pg_proc where oid=signature::regprocedure)
        or not has_function_privilege('authenticated',signature,'EXECUTE')then
        raise exception 'Invalid nearby public wrapper';end if;
    foreach role_name in array array['anon','yap_recommendation_worker','yap_feed_media_worker']loop
        if has_function_privilege(role_name,signature,'EXECUTE')then
            raise exception 'Nearby wrapper exposed to %',role_name;end if;
    end loop;
    if recsys.personalization_contract()->>'feature_version'<>'feed-features-v2'
        or recsys.personalization_contract()->>'policy_version'<>'hybrid-v2' then
        raise exception 'Unexpected preparation contract';end if;
    if abs(private.feed_geo_distance(0,179.9,0,-179.9)-22238.985)>1 then
        raise exception 'Geographic distance wraps incorrectly';end if;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$begin
    begin perform public.get_nearby_feed();raise exception 'Missing identity accepted';
    exception when insufficient_privilege then null;end;
end $$;
reset role;

-- Maintenance input is bounded before any source search or row mutation.
do $$begin
    begin perform recsys.claim_index_batch(extensions.gen_random_uuid(),'test','live',9);raise exception 'Oversized batch accepted';
    exception when invalid_parameter_value then null;end;
    begin perform recsys.enqueue_index_backfill(null,501);raise exception 'Unbounded backfill accepted';
    exception when invalid_parameter_value then null;end;
    begin perform recsys.claim_refresh_job(extensions.gen_random_uuid(),2);raise exception 'Unknown lane accepted';
    exception when invalid_parameter_value then null;end;
end $$;
rollback;
