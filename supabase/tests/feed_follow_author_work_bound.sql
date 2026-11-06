begin;
set local statement_timeout='60s';

-- Reproduce stale low-cardinality statistics, followed by a burst of new
-- authors. Fixture rows roll back; do not rely on planner statistics returning
-- to their prior values. Timing is not the assertion: count actual post tuples
-- fetched by the production RPC. The HTTP load test also checks cached plans
-- after this deliberately adverse statistics sample.
create temporary table feed_author_work_users on commit drop as
    select n,extensions.gen_random_uuid() id from generate_series(1,1001)n;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
    select id,false,false,'{"name":"Author work fixture"}'from feed_author_work_users;
savepoint author_work_padding;
insert into feed.posts(id,author_id,text,audience,language,creation_request)
    select extensions.gen_random_uuid(),u.id,'Rolled back physical padding','public','en','[]'
    from feed_author_work_users u cross join generate_series(1,10000)g where u.n=1;
rollback to savepoint author_work_padding;
insert into feed.posts(id,author_id,text,audience,language,creation_request)
    select extensions.gen_random_uuid(),u.id,'Small statistics sample','public','en','[]'
    from feed_author_work_users u cross join generate_series(1,4)g where u.n=1;
analyze feed.posts;
insert into feed.posts(id,author_id,text,audience,language,creation_request)
    select extensions.gen_random_uuid(),u.id,'New author work fixture','public','en','[]'
    from feed_author_work_users u cross join generate_series(1,10)g where u.n<=1000;
insert into feed.author_follows(follower_id,author_id,following,version)
    select r.id,a.id,true,1 from feed_author_work_users r cross join feed_author_work_users a
    where r.n=1001 and a.n<=1000;
-- Other sessions grow after the planner observed a small/empty table. Reading
-- one new session must not scan all of them again for every candidate post.
analyze feed.page_items;
create temporary table feed_author_work_sessions on commit drop as
    select extensions.gen_random_uuid() id from generate_series(1,250);
insert into feed.page_sessions(id,user_id,sort,page_size,epoch)
    select s.id,u.id,'friends',20,1 from feed_author_work_sessions s
    cross join feed_author_work_users u where u.n=1;
select set_config('request.jwt.claim.sub',(select id::text from feed_author_work_users where n=1001),true);
select set_config('yap_test.feed_posts_oid','feed.posts'::regclass::oid::text,true);
select set_config('yap_test.feed_page_items_oid','feed.page_items'::regclass::oid::text,true);

set local role authenticated;
set local plan_cache_mode=force_generic_plan;
-- Cache the actual rendering plan against a small page table, then grow other
-- sessions without invalidating that plan. A single fresh call misses the
-- production regression: reversed joins rescan every page for every post.
do $$begin
    for n in 1..6 loop perform public.get_friends_feed(null,-1,20);end loop;
end $$;
reset role;
insert into feed.page_items(session_id,position,post_id,post_version)
    select s.id,p.position,p.id,p.version from feed_author_work_sessions s cross join (
        select id,version,(row_number()over(order by id)-1)::integer position
        from feed.posts order by id limit 20)p;
set local role authenticated;
do $$declare before_read bigint;after_read bigint;before_items bigint;after_items bigint;page jsonb;begin
    select coalesce(seq_tup_read+idx_tup_fetch,0)into before_read
        from pg_stat_xact_user_tables where relid=current_setting('yap_test.feed_posts_oid')::oid;
    select coalesce(seq_tup_read+idx_tup_fetch,0)into before_items
        from pg_stat_xact_user_tables where relid=current_setting('yap_test.feed_page_items_oid')::oid;
    page:=public.get_friends_feed(null,-1,20);
    select coalesce(seq_tup_read+idx_tup_fetch,0)into after_read
        from pg_stat_xact_user_tables where relid=current_setting('yap_test.feed_posts_oid')::oid;
    select coalesce(seq_tup_read+idx_tup_fetch,0)into after_items
        from pg_stat_xact_user_tables where relid=current_setting('yap_test.feed_page_items_oid')::oid;
    if jsonb_array_length(page->'items')<>20 then raise exception 'Unfilled followed author page';end if;
    if after_read-before_read>50000 then
        raise exception 'Followed-author work regressed: % post tuples for 1000 authors/10004 posts',after_read-before_read;
    end if;
    if after_items-before_items>50000 then
        raise exception 'Session exclusion work regressed: % tuples for 5000 existing page items',after_items-before_items;
    end if;
    raise notice 'Followed-author read: % post tuples for 1000 authors/10004 posts',after_read-before_read;
    raise notice 'Session exclusion: % tuples for 5000 existing page items',after_items-before_items;
end $$;
reset role;
rollback;
