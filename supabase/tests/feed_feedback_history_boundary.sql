begin;

do $$declare table_name text;role_name text;begin
    foreach table_name in array array['recsys.feedback_facts','recsys.feedback_history_contract']loop
        if not(select relrowsecurity from pg_class where oid=table_name::regclass)then
            raise exception 'Feedback history missing RLS: %',table_name;end if;
        foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
            if has_table_privilege(role_name,table_name,'SELECT,INSERT,UPDATE,DELETE')then
                raise exception 'Feedback history exposed: % %',role_name,table_name;end if;
        end loop;
    end loop;
    if not exists(select 1 from recsys.feedback_history_contract where version=1 and retention_days=30
        and isfinite(started_at)and started_at<=statement_timestamp())then raise exception 'Missing feedback coverage boundary';end if;
end $$;

insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)values
 ('68000000-0000-4000-8000-000000000001',false,false,'{"name":"Feedback boundary fixture"}'),
 ('68000000-0000-4000-8000-000000000002',false,false,'{"name":"Feedback boundary fixture"}');
insert into feed.posts(id,author_id,text,audience,language,creation_request)values
 ('68000000-0000-4000-8000-000000000003','68000000-0000-4000-8000-000000000001','Test content','public','en','[]');
insert into recsys.deliveries(id,user_id,post_id,post_version,epoch,surface,model,embedding_model,delivered_at)values
 ('68000000-0000-4000-8000-000000000004','68000000-0000-4000-8000-000000000002','68000000-0000-4000-8000-000000000003',1,1,'direct','synthetic-test','synthetic-test',statement_timestamp()-interval '10 seconds');

select set_config('request.jwt.claim.sub','68000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select public.apply_feed_action('68000000-0000-4000-8000-000000000005','68000000-0000-4000-8000-000000000004','like',0);
select public.apply_feed_action('68000000-0000-4000-8000-000000000005','68000000-0000-4000-8000-000000000004','like',0);
select public.apply_feed_action('68000000-0000-4000-8000-000000000006','68000000-0000-4000-8000-000000000004','unlike',1);
reset role;
do $$begin
    if(select count(*)from recsys.feedback_facts where user_id='68000000-0000-4000-8000-000000000002')<>2 then
        raise exception 'Action retry duplicated a fact or invented attention';end if;
    if(select active from recsys.feedback_facts where request_id='68000000-0000-4000-8000-000000000006')is distinct from false then
        raise exception 'Unlike transition lost';end if;
    if exists(select 1 from recsys.feedback_facts where user_id='68000000-0000-4000-8000-000000000002'
        and(delivery_id is null or surface<>'direct'or state_version is null))then
        raise exception 'Authoritative action context missing';end if;
end $$;

set local role authenticated;
select public.record_feed_events('[{"event_id":"68000000-0000-4000-8000-000000000007","delivery_id":"68000000-0000-4000-8000-000000000004","kind":"impression","visible_ms":1000,"visible_fraction":0.75}]');
select public.record_feed_events('[{"event_id":"68000000-0000-4000-8000-000000000007","delivery_id":"68000000-0000-4000-8000-000000000004","kind":"impression","visible_ms":1000,"visible_fraction":0.75}]');
reset role;
do $$begin
    if(select count(*)from recsys.feedback_facts where user_id='68000000-0000-4000-8000-000000000002'and kind='impression')<>1 then
        raise exception 'Confirmed impression missing or repeated';end if;
    if exists(select 1 from recsys.feedback_facts where post_id='68000000-0000-4000-8000-000000000003'
        and context::text like '%Test content%')then raise exception 'Raw content retained in feedback journal';end if;
end $$;

-- The existing BEFORE trigger changes version on a text-only UPDATE. A column
-- list containing only version/deleted_at would silently miss this transition.
select set_config('request.jwt.claim.sub','68000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.edit_feed_post('68000000-0000-4000-8000-000000000003',1,'Changed text');
reset role;
do $$begin
    if not exists(select 1 from recsys.feedback_facts where post_id='68000000-0000-4000-8000-000000000003'
        and kind='content'and post_version=2 and active)then raise exception 'BEFORE-trigger content version not captured';end if;
end $$;

rollback;
