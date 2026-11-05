begin;

do $$
declare role_name text; signature text;
begin
    if not (select relrowsecurity from pg_class where oid='feed.author_follows'::regclass) then
        raise exception 'Follow relation missing RLS';
    end if;
    foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker'] loop
        if has_table_privilege(role_name,'feed.author_follows','SELECT,INSERT,UPDATE,DELETE') then
            raise exception 'Raw follow state exposed to %',role_name;
        end if;
    end loop;
    foreach signature in array array[
        'public.set_feed_author_followed(uuid,uuid,boolean,bigint)',
        'public.get_feed_author_follow_state(uuid)',
        'public.get_feed_following(uuid,uuid,integer)',
        'public.get_feed_followers(uuid,uuid,integer)'
    ] loop
        if not has_function_privilege('authenticated',signature,'EXECUTE') then
            raise exception 'Missing authenticated RPC grant: %',signature;
        end if;
        if (select prosecdef from pg_proc where oid=signature::regprocedure) then
            raise exception 'Public follow wrapper is definer: %',signature;
        end if;
        foreach role_name in array array['anon','yap_recommendation_worker','yap_feed_media_worker'] loop
            if has_function_privilege(role_name,signature,'EXECUTE') then
                raise exception 'Unexpected RPC grant to %: %',role_name,signature;
            end if;
        end loop;
    end loop;
    foreach signature in array array[
        'private.feed_follow_user_visible(uuid,uuid)',
        'private.feed_follow_state_json(uuid,uuid)',
        'private.queue_feed_follow_change()',
        'private.remove_feed_follows_on_block()',
        'private.feed_timeline_authors(uuid)'
    ] loop
        foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker'] loop
            if has_function_privilege(role_name,signature,'EXECUTE') then
                raise exception 'Internal follow helper exposed: % to %',signature,role_name;
            end if;
        end loop;
    end loop;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
    begin
        perform public.get_feed_following();
        raise exception 'Missing identity accepted';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;
rollback;
