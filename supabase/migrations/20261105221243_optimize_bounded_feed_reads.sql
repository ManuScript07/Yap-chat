-- Stop bounded nearby scans as soon as a full page and lookahead are known.
-- The RPC, rate limits, visibility rules and cursor format are unchanged.
create or replace function private.get_nearby_feed_impl(requested_session uuid,after_position integer,requested_limit integer,requested_radius_km integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
    state recsys.user_states%rowtype;
    s feed.page_sessions%rowtype;
    page feed.page_metadata%rowtype;
    origin public.user_locations%rowtype;
    selected uuid[];consumed integer;more boolean;target uuid;
    candidate feed.posts%rowtype;
    -- Negative author/audience decisions live only within this RPC. Accepted
    -- posts always pass the full live check, including every original edge.
    rejected_author_scopes text[]:=array[]::text[];author_scope text;
    scan_at timestamptz;scan_id uuid;
    selected_at timestamptz;selected_id uuid;selected_consumed integer;
    current_post feed.posts%rowtype;receipt uuid;cursor integer;items jsonb;
    longitude_delta double precision;
begin
    perform private.require_social_account();perform private.consume_social_quota('nearby_read');
    if requested_limit is null or requested_limit not between 1 and 30 or after_position is null or after_position< -1
        or requested_radius_km is null or requested_radius_km not between 1 and 50 then
        raise exception using errcode='22023',message='invalid_nearby_cursor';end if;
    select * into origin from public.user_locations where user_id=auth.uid()and updated_at>statement_timestamp()-interval '12 hours';
    if not found then raise exception using errcode='PT412',message='nearby_location_required';end if;
    state:=private.lock_recommendation_user(auth.uid());
    if requested_session is null then
        if after_position<> -1 then raise exception using errcode='22023',message='invalid_nearby_cursor';end if;
        if(select count(*)from feed.page_sessions where user_id=auth.uid()and expires_at>statement_timestamp())>=128 then
            raise exception using errcode='42901',message='feed_sessions_rate_limited';end if;
        insert into feed.page_sessions(id,user_id,sort,page_size,epoch,origin_latitude,origin_longitude,radius_km)
            values(extensions.gen_random_uuid(),auth.uid(),'nearby',requested_limit,state.epoch,origin.latitude,origin.longitude,requested_radius_km)
            returning * into s;
    else
        select * into s from feed.page_sessions where id=requested_session and user_id=auth.uid()for update;
        if not found then raise exception using errcode='PT404',message='nearby_session_not_found';end if;
        if s.sort<>'nearby'or s.page_size<>requested_limit or s.radius_km<>requested_radius_km then
            raise exception using errcode='22023',message='nearby_cursor_context_mismatch';end if;
        if s.epoch<>state.epoch then raise exception using errcode='PT409',message='nearby_session_invalidated';end if;
        if s.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='nearby_session_expired';end if;
    end if;
    select * into page from feed.page_metadata where session_id=s.id and page_metadata.after_position=get_nearby_feed_impl.after_position;
    if not found then
        if after_position<>s.next_position-1 then raise exception using errcode='22023',message='invalid_nearby_cursor';end if;
        if s.next_position>0 and exists(select 1 from feed.page_metadata where session_id=s.id and not has_more)then
            raise exception using errcode='22023',message='nearby_page_exhausted';end if;
        longitude_delta:=private.feed_geo_longitude_delta(s.origin_latitude,s.radius_km*1000.0);
        -- Stream the bounded chronological window. A sort over a materialized
        -- eligibility CTE evaluates every access check before LIMIT; stopping
        -- here needs only page_size+1 eligible rows in a dense visible feed.
        -- Preserve the scan budget and the existing cursor checkpoint exactly.
        selected:=array[]::uuid[];consumed:=0;more:=false;
        for candidate in
            select p.* from feed.posts p where p.latitude is not null and p.deleted_at is null and p.moderation_status='allowed'
                and p.author_id<>auth.uid()and p.created_at<=s.created_at and p.created_at> s.created_at-interval '7 days'
                and p.latitude between s.origin_latitude-degrees(s.radius_km*1000.0/6371000)and s.origin_latitude+degrees(s.radius_km*1000.0/6371000)
                and(abs(p.longitude-s.origin_longitude)<=longitude_delta or abs(p.longitude-s.origin_longitude)>=360-longitude_delta)
                and(s.scan_created_at is null or p.created_at<s.scan_created_at or(p.created_at=s.scan_created_at and p.id>s.scan_post_id))
            order by p.created_at desc,p.id limit 2000
        loop
            author_scope:=candidate.author_id::text||':'||candidate.audience;
            if not(author_scope=any(rejected_author_scopes))and private.feed_geo_distance(candidate.latitude,candidate.longitude,s.origin_latitude,s.origin_longitude)<=s.radius_km*1000 then
              if private.feed_post_accessible(auth.uid(),candidate) then
                if cardinality(selected)=requested_limit then
                    more:=true;
                    -- The lookahead belongs to the next page. As before, a
                    -- full page consumes only through its last selected row.
                    consumed:=selected_consumed;scan_at:=selected_at;scan_id:=selected_id;
                    exit;
                end if;
                selected:=array_append(selected,candidate.id);
                selected_consumed:=consumed+1;selected_at:=candidate.created_at;selected_id:=candidate.id;
              elsif not private.feed_post_visible(auth.uid(),candidate.author_id,candidate.audience)then
                -- A per-post hide or inaccessible original must NOT reject an
                -- otherwise visible author's remaining posts.
                rejected_author_scopes:=array_append(rejected_author_scopes,author_scope);
              end if;
            end if;
            consumed:=consumed+1;scan_at:=candidate.created_at;scan_id:=candidate.id;
        end loop;
        -- A fully inaccessible window still advances; no unlimited refill.
        more:=more or consumed=2000;
        cursor:=s.next_position;
        foreach target in array selected loop
            select * into current_post from feed.posts where id=target;
            insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
                values(auth.uid(),current_post.id,current_post.version,state.epoch,'nearby','nearby-v1',
                  'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')returning id into receipt;
            insert into feed.page_items(session_id,position,post_id,post_version,delivery_id)
                values(s.id,cursor,current_post.id,current_post.version,receipt);cursor:=cursor+1;
        end loop;
        update feed.page_sessions set next_position=s.next_position+consumed,
            scan_created_at=case when consumed>0 then scan_at else scan_created_at end,
            scan_post_id=case when consumed>0 then scan_id else scan_post_id end where id=s.id;
        insert into feed.page_metadata(session_id,after_position,last_position,has_more)
            values(s.id,after_position,s.next_position+consumed-1,more)returning * into page;
    end if;
    -- Materialize the issued page before permissions. With stale/small-table
    -- estimates a cached plan can otherwise check all posts once per item.
    with current_page as materialized(
        select i.position,p as post,d.id delivery_id,d.valid_until delivery_expires_at,
            coalesce(v.version,0)action_version,l.post_id is not null liked
        from feed.page_items i join feed.posts p on p.id=i.post_id and p.version=i.post_version
        join recsys.deliveries d on d.id=i.delivery_id and d.epoch=state.epoch and d.valid_until>statement_timestamp()
        left join recsys.post_action_versions v on v.user_id=auth.uid()and v.post_id=p.id
        left join feed.post_likes l on l.user_id=auth.uid()and l.post_id=p.id
        where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position
    )select coalesce(jsonb_agg(jsonb_build_object('position',c.position,'delivery_id',c.delivery_id,
        'delivery_expires_at',c.delivery_expires_at,'post',private.feed_post_json(c.post)
            ||jsonb_build_object('action_version',c.action_version,'liked',c.liked))order by c.position),'[]')into items
        from current_page c where private.feed_post_accessible(auth.uid(),c.post);
    return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'radius_km',s.radius_km,'items',items,'has_more',page.has_more,
        'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;

-- Materialize only bounded candidate rows before the final access/filter join.
create or replace function recsys.load_refresh_candidates(viewer uuid, requested_lease uuid, requested_epoch integer,
  requested_model text, requested_profile jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_refresh_lease(viewer,requested_lease);
  if not exists(select 1 from recsys.user_states where user_id=viewer and epoch=requested_epoch) then return '[]'::jsonb; end if;
  if jsonb_typeof(requested_profile)<>'array' or jsonb_array_length(requested_profile)>8 then
    raise exception using errcode='22023',message='invalid_profile'; end if;
  with social as materialized(
    select case when f.user_one_id=viewer then f.user_two_id else f.user_one_id end author_id
      from public.friendships f where f.user_one_id=viewer or f.user_two_id=viewer
  ), followed as materialized(
    select author_id from feed.author_follows where follower_id=viewer and following
      and private.feed_follow_user_visible(viewer,author_id)
  ), affinity as materialized(
    select distinct author_id from(
      (select p.author_id from feed.post_likes l join feed.posts p on p.id=l.post_id and p.version=l.post_version
        where l.user_id=viewer and l.epoch=requested_epoch and l.created_at>statement_timestamp()-interval '30 days'
          and p.deleted_at is null and p.moderation_status='allowed'and private.feed_post_visible(viewer,p.author_id,p.audience)
        order by l.created_at desc,l.post_id limit 100)
      union all
      (select p.author_id from recsys.daily_exposures e join feed.posts p on p.id=e.post_id and p.version=e.post_version
        where e.user_id=viewer and e.epoch=requested_epoch and e.engaged_at>statement_timestamp()-interval '7 days'
          and(e.active_ms>=5000 or e.opened)and p.deleted_at is null and p.moderation_status='allowed'and private.feed_post_visible(viewer,p.author_id,p.audience)
        order by e.engaged_at desc,e.post_id limit 100)
      union all
      (select p.author_id from recsys.social_feedback f join feed.posts p on p.id=f.post_id and p.version=f.post_version
       where f.user_id=viewer and f.epoch=requested_epoch and f.created_at>statement_timestamp()-interval '30 days'
       and private.social_feedback_allowed(viewer,f)and private.feed_post_accessible(viewer,p)
       order by f.created_at desc,f.post_id limit 100)
    )evidence where private.feed_post_visible(viewer,author_id,'friends')or private.feed_post_visible(viewer,author_id,'public')
    order by author_id limit 20
  ), seen as materialized(select post_id,max(last_seen_at)at from recsys.daily_exposures
    where user_id=viewer and last_seen_at>statement_timestamp()-interval '24 hours' group by post_id),
  topics as materialized(
    select (c->>'vector')::extensions.vector(384) embedding from jsonb_array_elements(requested_profile)c
      where not(c->>'negative')::boolean
  ), pool as (
    (select id,'fresh'::text source from feed.posts where created_at>statement_timestamp()-interval '7 days' and author_id<>viewer
      and deleted_at is null and moderation_status='allowed' and not exists(select 1 from seen where seen.post_id=feed.posts.id)
      order by created_at desc,id limit 300)
    union all
    (select p.id,'social' from social s join feed.posts p on p.author_id=s.author_id
      where p.created_at>statement_timestamp()-interval '7 days' and p.deleted_at is null and p.moderation_status='allowed'
      order by p.created_at desc,p.id limit 200)
    union all
    (select p.id,'following' from followed f cross join lateral(
      select post.id,post.created_at from feed.posts post where post.author_id=f.author_id
        and post.created_at>statement_timestamp()-interval '7 days'
        and post.deleted_at is null and post.moderation_status='allowed'
      order by post.created_at desc,post.id limit 10)p
      order by p.created_at desc,p.id limit 200)
    union all
    (select p.id,'author_affinity' from affinity a cross join lateral(
      select id,created_at from feed.posts where author_id=a.author_id and deleted_at is null and moderation_status='allowed'
        and created_at>statement_timestamp()-interval '7 days'order by created_at desc,id limit 10
    )p order by p.created_at desc,p.id limit 150)
    union all
    (select p.id,'popular' from (select post_id,quality from recsys.post_statistics order by quality desc,post_id limit 500)st join feed.posts p on p.id=st.post_id
      where p.created_at>statement_timestamp()-interval '7 days' and p.deleted_at is null and p.moderation_status='allowed'
      order by st.quality desc,p.id limit 150)
    union all
    (select p.id,'discovery' from (select * from feed.posts where author_id<>viewer and deleted_at is null and moderation_status='allowed'
      and created_at>statement_timestamp()-interval '7 days'order by created_at desc,id limit 1000)p left join recsys.author_statistics coverage on coverage.author_id=p.author_id
      where p.created_at>statement_timestamp()-interval '7 days' and p.deleted_at is null and p.moderation_status='allowed'
      and coalesce(coverage.viewers,0)<20 and coalesce(coverage.impressions,0)<200 and not exists(select 1 from seen where seen.post_id=p.id)
      order by p.created_at desc,p.id limit 150)
    union all
    (select p.id,'read_fallback' from seen join feed.posts p on p.id=seen.post_id
      where p.created_at>statement_timestamp()-interval '7 days' and p.deleted_at is null and p.moderation_status='allowed'
      order by seen.at,p.id limit 200)
    union all
    select found.post_id,'semantic' from topics t cross join lateral(
      select em.post_id from recsys.post_embeddings em where em.model=requested_model
        order by em.embedding operator(extensions.<=>) t.embedding limit 100
    )found
    union all
    (select r.original_post_id,'friends_repost'from social f join feed.reposts r on r.author_id=f.author_id
     where r.post_id is null and r.deleted_at is null and r.moderation_status='allowed'
     and r.created_at>statement_timestamp()-interval '7 days'and private.feed_post_visible(viewer,r.author_id,r.audience)
     order by r.created_at desc,r.id limit 200)
    union all
    (select p.id,'nearby' from (
      select post.id,post.latitude,post.longitude,l.latitude origin_lat,l.longitude origin_lon
      from public.user_locations l join feed.posts post on post.latitude is not null
      where l.user_id=viewer and l.updated_at>statement_timestamp()-interval '12 hours'
        and post.created_at>statement_timestamp()-interval '7 days'and post.author_id<>viewer
        and post.deleted_at is null and post.moderation_status='allowed'
        and post.latitude between l.latitude-degrees(50000.0/6371000)and l.latitude+degrees(50000.0/6371000)
        and(abs(post.longitude-l.longitude)<=private.feed_geo_longitude_delta(l.latitude,50000)
          or abs(post.longitude-l.longitude)>=360-private.feed_geo_longitude_delta(l.latitude,50000))
      order by post.created_at desc,post.id limit 500
    )p where private.feed_geo_distance(p.latitude,p.longitude,p.origin_lat,p.origin_lon)<=50000 limit 50)
  ), ids as materialized(select id,array_agg(distinct source order by source) sources from pool group by id),
  -- Fence the bounded retrieval result before applying expensive per-post
  -- permissions. Otherwise the planner may scan/check every post first, then
  -- repeatedly join that result to each candidate under a poor row estimate.
  candidate_posts as materialized(select p.* from ids join feed.posts p on p.id=ids.id),
  authors as materialized(
    select distinct p.author_id,p.audience from candidate_posts p
  ), allowed as materialized(select a.* from authors a where private.feed_post_visible(viewer,a.author_id,a.audience)),
  candidates as (
    select p.id,p.author_id,p.version,p.created_at,coalesce(em.embedding::text,'') vector,ids.sources,
      (exists(select 1 from social where author_id=p.author_id)or exists(select 1 from affinity where author_id=p.author_id)or exists(select 1 from followed where author_id=p.author_id)or 'friends_repost'=any(ids.sources)) social,'nearby'=any(ids.sources)nearby,coalesce(st.impressions,0)impressions,
      coalesce(st.likes,0)likes,coalesce(st.reposts,0)reposts,coalesce(coverage.impressions,0)author_impressions,coalesce(coverage.viewers,0)author_viewers,seen.at is not null seen
    from ids join candidate_posts p on p.id=ids.id join allowed a on a.author_id=p.author_id and a.audience=p.audience
    left join recsys.post_embeddings em on em.post_id=p.id and em.post_version=p.version and em.model=requested_model
    left join recsys.post_statistics st on st.post_id=p.id left join recsys.author_statistics coverage on coverage.author_id=p.author_id left join seen on seen.post_id=p.id
    where p.author_id<>viewer and private.feed_post_accessible(viewer,p)
      and p.created_at>statement_timestamp()-interval '7 days'
      and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
      and not exists(select 1 from recsys.semantic_suppressions h where h.user_id=viewer and h.post_id=p.id)
    order by p.id limit 1200
  )select coalesce(jsonb_agg(to_jsonb(c)order by c.id),'[]'::jsonb)into result from candidates c;
  return result;
end $$;

-- The same page boundary protects friends and personalized reads.
create or replace function private.get_friends_feed_impl(requested_session uuid,after_position integer,requested_limit integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare s feed.page_sessions%rowtype;page feed.page_metadata%rowtype;state recsys.user_states%rowtype;
 chosen uuid[];connections uuid[];items jsonb;more boolean;cursor integer;target uuid;current_post feed.posts%rowtype;delivery uuid;
begin
 perform private.require_social_account();perform private.consume_social_quota('friends_read');
 if requested_limit is null or requested_limit not between 1 and 30 or after_position is null or after_position< -1 then
 raise exception using errcode='22023',message='invalid_friends_cursor';end if;
 state:=private.lock_recommendation_user(auth.uid());
 if requested_session is null then
  if after_position<> -1 then raise exception using errcode='22023',message='invalid_friends_cursor';end if;
  if(select count(*)from feed.page_sessions where user_id=auth.uid()and expires_at>statement_timestamp())>=128 then
   raise exception using errcode='42901',message='feed_sessions_rate_limited';end if;
  insert into feed.page_sessions(id,user_id,sort,page_size,epoch)values(extensions.gen_random_uuid(),auth.uid(),'friends',requested_limit,state.epoch)returning * into s;
 else
  select * into s from feed.page_sessions where id=requested_session and user_id=auth.uid()for update;
  if not found then raise exception using errcode='PT404',message='friends_session_not_found';end if;
  if s.epoch<>state.epoch then raise exception using errcode='PT409',message='friends_session_invalidated';end if;
  if s.sort<>'friends'or s.page_size<>requested_limit then raise exception using errcode='22023',message='friends_cursor_context_mismatch';end if;
  if s.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='friends_session_expired';end if;
 end if;
 select array_agg(author_id)into connections from private.feed_timeline_authors(auth.uid());
 select * into page from feed.page_metadata where session_id=s.id and page_metadata.after_position=get_friends_feed_impl.after_position;
 if not found then
  if after_position<>s.next_position-1 then raise exception using errcode='22023',message='invalid_friends_cursor';end if;
  with friends as materialized(select unnest(connections)id),
  events as(
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select p from feed.posts p where p.author_id=f.id and p.created_at<=s.created_at
     and p.deleted_at is null and p.moderation_status='allowed'
     -- Connection identities were checked once above. Inline cheap row filters
     -- before the per-author limit; resolve full chains only for actual quotes.
     and(p.audience='public'or exists(select 1 from public.friendships rel
       where rel.user_one_id=least(auth.uid(),p.author_id)and rel.user_two_id=greatest(auth.uid(),p.author_id)))
     and not exists(select 1 from feed.reported_content_hides h where h.user_id=auth.uid()and h.target_type='post'and h.target_id=p.id)
     and(not p.is_repost or private.feed_post_accessible(auth.uid(),p))
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
     order by p.created_at desc,p.id)
    select (p).id,(p).created_at at from unseen
    limit requested_limit+1)found
   union all
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select r,original from feed.reposts r join feed.posts original on original.id=r.original_post_id
     where r.author_id=f.id and r.created_at<=s.created_at and r.post_id is null
     and r.deleted_at is null and r.moderation_status='allowed'
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=r.original_post_id)
     order by r.created_at desc,r.id)
    select (r).original_post_id id,(r).created_at at from unseen
    where private.feed_post_visible(auth.uid(),(r).author_id,(r).audience)
    and private.feed_post_accessible(auth.uid(),original)limit requested_limit+1)found
  ),recent as(select id,max(at)at from events group by id),eligible as(
   select p.id,r.at from recent r join feed.posts p on p.id=r.id where
   not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
   order by r.at desc,p.id limit requested_limit+1)
  select array_agg(id order by at desc,id)into chosen from eligible;
  chosen:=coalesce(chosen,'{}');more:=cardinality(chosen)>requested_limit;chosen:=chosen[1:requested_limit];cursor:=s.next_position;
  foreach target in array chosen loop
   select * into current_post from feed.posts where id=target;
   insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
   values(auth.uid(),current_post.id,current_post.version,state.epoch,'friends','friends-v1',
    'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')returning id into delivery;
   insert into feed.page_items(session_id,position,post_id,post_version,delivery_id)values(s.id,cursor,current_post.id,current_post.version,delivery);cursor:=cursor+1;
  end loop;
  update feed.page_sessions set next_position=cursor where id=s.id;
  insert into feed.page_metadata(session_id,after_position,last_position,has_more)values(s.id,after_position,cursor-1,more)returning * into page;
 end if;
 with friends as materialized(select unnest(connections)id),current_page as materialized(
  select i.position,p as post,d.id delivery_id,d.valid_until delivery_expires_at,
   coalesce(v.version,0)action_version,l.post_id is not null liked
  from feed.page_items i join feed.posts p on p.id=i.post_id and p.version=i.post_version
  join recsys.deliveries d on d.id=i.delivery_id and d.epoch=state.epoch and d.valid_until>statement_timestamp()
  left join recsys.post_action_versions v on v.user_id=auth.uid()and v.post_id=p.id
  left join feed.post_likes l on l.user_id=auth.uid()and l.post_id=p.id
  where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position
 )select coalesce(jsonb_agg(jsonb_build_object('position',c.position,'delivery_id',c.delivery_id,
  'delivery_expires_at',c.delivery_expires_at,'post',private.feed_post_json(c.post)
    ||jsonb_build_object('action_version',c.action_version,'liked',c.liked))order by c.position),'[]')into items
 from current_page c where private.feed_post_accessible(auth.uid(),c.post)
 and(exists(select 1 from friends f where f.id=(c.post).author_id)or exists(select 1 from friends f join feed.reposts r on r.author_id=f.id
  where r.original_post_id=(c.post).id and r.post_id is null and r.created_at<=s.created_at and r.deleted_at is null and r.moderation_status='allowed'
  and private.feed_post_visible(auth.uid(),r.author_id,r.audience)));
 return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'items',items,'has_more',page.has_more,
 'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;

create or replace function private.get_for_you_feed_impl(requested_session uuid, after_position integer, requested_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; snapshot recsys.feed_snapshots%rowtype; item record; delivery uuid; delivery_until timestamptz;
  items jsonb:='[]'::jsonb; has_more boolean:=false; next_position integer:=after_position; count_items integer:=0; refresh_status text;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('recommendation_read');
  if requested_limit is null or requested_limit not between 1 and 30 or after_position is null
    or after_position not between -1 and 199 or (requested_session is null and after_position<>-1)then
    raise exception using errcode='22023',message='invalid_feed_cursor';
  end if;
  s:=private.lock_recommendation_user(auth.uid());
  if requested_session is not null then
    select * into snapshot from recsys.feed_snapshots where id=requested_session and user_id=auth.uid();
    if not found then raise exception using errcode='PT404',message='feed_session_not_found'; end if;
    if snapshot.epoch<>s.epoch then raise exception using errcode='PT409',message='feed_session_invalidated'; end if;
    if snapshot.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='feed_session_expired'; end if;
  else
    select * into snapshot from recsys.feed_snapshots where id=s.current_snapshot and user_id=auth.uid()
      and epoch=s.epoch and expires_at>statement_timestamp();
    if not found then
      s.current_snapshot:=private.create_recommendation_fallback(s);
      select * into snapshot from recsys.feed_snapshots where id=s.current_snapshot;
    end if;
  end if;
  if s.prepared_at is null or s.prepared_at<statement_timestamp()-interval '30 seconds' or s.processed_revision<s.revision then
    perform private.queue_recommendation_refresh(auth.uid(),s.revision,true);
  end if;
  -- Filter first, then take limit+1: invisible/deleted/edited positions neither
  -- leak through an old session nor cause premature end-of-pagination.
  for item in select i.*,p as post from recsys.feed_snapshot_items i join feed.posts p on p.id=i.post_id
    where i.snapshot_id=snapshot.id and i.position>after_position and i.post_version=p.version
    order by i.position limit 200 loop
    -- The snapshot is bounded to 200. Stream its reserve and check only rows
    -- actually visited, preventing pushdown over the entire posts table.
    if not private.recommendation_post_allowed(auth.uid(),item.post)then continue;end if;
    if count_items=requested_limit then has_more:=true;exit;end if;
    select id,valid_until into delivery,delivery_until from recsys.deliveries where user_id=auth.uid() and snapshot_id=snapshot.id and position=item.position;
    if not found then
      insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,snapshot_id,position,model,embedding_model,features,features_at)
        values(auth.uid(),item.post_id,item.post_version,s.epoch,'for_you',snapshot.id,item.position,snapshot.model,snapshot.embedding_model,item.features,snapshot.features_at)
        returning id,valid_until into delivery,delivery_until;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object('position',item.position,'delivery_id',delivery,'delivery_expires_at',delivery_until,
      'post',private.feed_post_json(item.post)||jsonb_build_object('action_version',
        coalesce((select version from recsys.post_action_versions where user_id=auth.uid()and post_id=item.post_id),0),
        'liked',exists(select 1 from feed.post_likes l
        where l.user_id=auth.uid() and l.post_id=item.post_id)), 'reasons',item.reasons));
    count_items:=count_items+1;next_position:=item.position;
  end loop;
  select case when attempts>=8 then 'failed' when attempts>0 and last_error is not null then 'retrying' else 'queued' end
    into refresh_status from recsys.refresh_jobs where user_id=auth.uid();
  return jsonb_build_object('session_id',snapshot.id,'items',items,'expires_at',snapshot.expires_at,'model',snapshot.model,'versions',jsonb_build_object('features',snapshot.feature_version,'policy',snapshot.policy_version,'embedding_space',snapshot.embedding_space),
    'contract_version',1,'has_more',has_more,
    'next_cursor',case when has_more then jsonb_build_object('session_id',snapshot.id,'after_position',next_position)else null end,
    'refresh',jsonb_build_object('status',coalesce(refresh_status,'fresh'),'revision',s.revision,'processed_revision',s.processed_revision,
      'prepared_at',s.prepared_at));
end $$;

notify pgrst,'reload schema';

