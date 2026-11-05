-- Geographic discovery is chronological, bounded and independent of ML.
create index feed_posts_geotag_idx on feed.posts(latitude,created_at desc,id)
    where latitude is not null and deleted_at is null and moderation_status='allowed';
alter table feed.page_sessions add column origin_latitude double precision,
    add column origin_longitude double precision,add column radius_km integer,
    add column scan_created_at timestamptz,add column scan_post_id uuid;
do $$declare constraint_name text;begin
    for constraint_name in select conname from pg_constraint
        where conrelid='feed.page_sessions'::regclass and contype='c'and pg_get_constraintdef(oid)like '%sort%'
    loop execute 'alter table feed.page_sessions drop constraint '||quote_ident(constraint_name);end loop;
end $$;
alter table feed.page_sessions
    add constraint feed_session_sort check(sort in('popular','old','new','friends','nearby')),
    add constraint feed_session_target check((sort in('friends','nearby'))=(post_id is null)),
    add constraint feed_session_root check(sort not in('friends','nearby')or root_id is null),
    add constraint feed_session_origin check((sort='nearby')=(origin_latitude is not null and origin_longitude is not null and radius_km is not null)),
    add constraint feed_session_radius check(radius_km between 1 and 50),
    add constraint feed_session_scan_key check((scan_created_at is null)=(scan_post_id is null));

create function private.feed_geo_distance(lat double precision,lon double precision,origin_lat double precision,origin_lon double precision)
returns double precision language sql immutable strict set search_path='' as $$
    select 6371000*2*asin(sqrt(least(1.0,power(sin(radians(lat-origin_lat)/2),2)
        +cos(radians(lat))*cos(radians(origin_lat))*power(sin(radians(lon-origin_lon)/2),2))));
$$;
create function private.feed_geo_longitude_delta(origin_lat double precision,radius_m double precision)
returns double precision language sql immutable strict set search_path='' as $$
    select case when abs(origin_lat)+degrees(radius_m/6371000)>=90 then 180.0
        else degrees(asin(least(1.0,sin(radius_m/6371000)/greatest(.0000001,cos(radians(origin_lat))))))end;
$$;

create function private.get_nearby_feed_impl(requested_session uuid,after_position integer,requested_limit integer,requested_radius_km integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
    state recsys.user_states%rowtype;
    s feed.page_sessions%rowtype;
    page feed.page_metadata%rowtype;
    origin public.user_locations%rowtype;
    raw_ids uuid[];raw_times timestamptz[];selected uuid[];ordinals integer[];
    count_raw integer;consumed integer;more boolean;target uuid;
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
        -- At most 2000 cheap spatial candidates per request. The cursor advances
        -- over examined rows even if a whole window is inaccessible: no loops,
        -- silent truncation or unlimited searches to fill one client page.
        with ordered as materialized(
            select p from feed.posts p where p.latitude is not null and p.deleted_at is null and p.moderation_status='allowed'
                and p.author_id<>auth.uid()and p.created_at<=s.created_at and p.created_at> s.created_at-interval '7 days'
                and p.latitude between s.origin_latitude-degrees(s.radius_km*1000.0/6371000)and s.origin_latitude+degrees(s.radius_km*1000.0/6371000)
                and(abs(p.longitude-s.origin_longitude)<=longitude_delta or abs(p.longitude-s.origin_longitude)>=360-longitude_delta)
                and(s.scan_created_at is null or p.created_at<s.scan_created_at or(p.created_at=s.scan_created_at and p.id>s.scan_post_id))
            order by p.created_at desc,p.id limit 2000
        ),numbered as materialized(
            select p,row_number()over(order by(p).created_at desc,(p).id)::integer n from ordered
        ),eligible as materialized(
            select(p).id,n from numbered
                where private.feed_geo_distance((p).latitude,(p).longitude,s.origin_latitude,s.origin_longitude)<=s.radius_km*1000
                and private.feed_post_accessible(auth.uid(),p)
            order by n limit requested_limit+1
        )select(select array_agg((p).id order by n)from numbered),
            (select array_agg((p).created_at order by n)from numbered),
            array_agg(id order by n),array_agg(n order by n)into raw_ids,raw_times,selected,ordinals from eligible;
        count_raw:=coalesce(cardinality(raw_ids),0);selected:=coalesce(selected,'{}');
        more:=cardinality(selected)>requested_limit or count_raw=2000;
        consumed:=case when cardinality(selected)>requested_limit then ordinals[requested_limit]else count_raw end;
        selected:=selected[1:requested_limit];cursor:=s.next_position;
        foreach target in array selected loop
            select * into current_post from feed.posts where id=target;
            insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
                values(auth.uid(),current_post.id,current_post.version,state.epoch,'nearby','nearby-v1',
                  'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')returning id into receipt;
            insert into feed.page_items(session_id,position,post_id,post_version,delivery_id)
                values(s.id,cursor,current_post.id,current_post.version,receipt);cursor:=cursor+1;
        end loop;
        update feed.page_sessions set next_position=s.next_position+consumed,
            scan_created_at=case when consumed>0 then raw_times[consumed]else scan_created_at end,
            scan_post_id=case when consumed>0 then raw_ids[consumed]else scan_post_id end where id=s.id;
        insert into feed.page_metadata(session_id,after_position,last_position,has_more)
            values(s.id,after_position,s.next_position+consumed-1,more)returning * into page;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('position',i.position,'delivery_id',d.id,'delivery_expires_at',d.valid_until,
        'post',private.feed_post_json(p)||jsonb_build_object('action_version',coalesce(v.version,0),'liked',l.post_id is not null))order by i.position),'[]')into items
        from feed.page_items i join feed.posts p on p.id=i.post_id and p.version=i.post_version
        join recsys.deliveries d on d.id=i.delivery_id and d.epoch=state.epoch and d.valid_until>statement_timestamp()
        left join recsys.post_action_versions v on v.user_id=auth.uid()and v.post_id=p.id
        left join feed.post_likes l on l.user_id=auth.uid()and l.post_id=p.id
        where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position
            and private.feed_post_accessible(auth.uid(),p);
    return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'radius_km',s.radius_km,'items',items,'has_more',page.has_more,
        'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;
create function public.get_nearby_feed(requested_session uuid default null,after_position integer default -1,
    requested_limit integer default 20,requested_radius_km integer default 50)
returns jsonb language sql security invoker set search_path='' as $$
    select private.get_nearby_feed_impl(requested_session,after_position,requested_limit,requested_radius_km);
$$;


create or replace function private.consume_social_quota(op text)
returns void language plpgsql security definer set search_path=''as $$
declare per_min integer;per_day integer;accepted integer;today date:=(statement_timestamp()at time zone 'UTC')::date;
begin
 case op
 when 'follow_write' then per_min:=120;per_day:=2000;
 when 'follow_create' then per_min:=30;per_day:=500;
 when 'follow_state_read' then per_min:=120;per_day:=86400;
 when 'following_read' then per_min:=60;per_day:=86400;
 when 'followers_read' then per_min:=60;per_day:=86400;
 when 'comment_create' then per_min:=30;per_day:=500;
 when 'comment_create_request' then per_min:=60;per_day:=86400;
 when 'comment_edit' then per_min:=30;per_day:=1000;
 when 'comment_delete' then per_min:=60;per_day:=1000;
 when 'comment_action' then per_min:=120;per_day:=20000;
 when 'comment_read' then per_min:=60;per_day:=86400;
 when 'report_post' then per_min:=5;per_day:=20;
 when 'report_comment' then per_min:=5;per_day:=30;
 when 'report_request' then per_min:=60;per_day:=86400;
 when 'nearby_read' then per_min:=60;per_day:=86400;
 when 'friends_read' then per_min:=60;per_day:=86400;
 else raise exception using errcode='22023',message='invalid_social_operation';end case;
 insert into private.feed_social_limits as q(user_id,operation,window_started_at,requests,day_utc,day_count)
 values(auth.uid(),op,statement_timestamp(),1,today,1)
 on conflict(user_id,operation)do update set
 window_started_at=case when q.window_started_at<=statement_timestamp()-interval '1 minute'then statement_timestamp()else q.window_started_at end,
 requests=case when q.window_started_at<=statement_timestamp()-interval '1 minute'then 1 else q.requests+1 end,
 day_utc=today,day_count=case when q.day_utc<today then 1 else q.day_count+1 end
 where(q.window_started_at<=statement_timestamp()-interval '1 minute'or q.requests<per_min)and(q.day_utc<today or q.day_count<per_day)
 returning requests into accepted;
 if accepted is null then raise exception using errcode='42901',message='social_rate_limited';end if;
end $$;

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
  authors as materialized(
    select distinct p.author_id,p.audience from ids join feed.posts p on p.id=ids.id
  ), allowed as materialized(select a.* from authors a where private.feed_post_visible(viewer,a.author_id,a.audience)),
  candidates as (
    select p.id,p.author_id,p.version,p.created_at,coalesce(em.embedding::text,'') vector,ids.sources,
      (exists(select 1 from social where author_id=p.author_id)or exists(select 1 from affinity where author_id=p.author_id)or exists(select 1 from followed where author_id=p.author_id)or 'friends_repost'=any(ids.sources)) social,'nearby'=any(ids.sources)nearby,coalesce(st.impressions,0)impressions,
      coalesce(st.likes,0)likes,coalesce(st.reposts,0)reposts,coalesce(coverage.impressions,0)author_impressions,coalesce(coverage.viewers,0)author_viewers,seen.at is not null seen
    from ids join feed.posts p on p.id=ids.id join allowed a on a.author_id=p.author_id and a.audience=p.audience
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

revoke all on function private.feed_geo_distance(double precision,double precision,double precision,double precision),
    private.feed_geo_longitude_delta(double precision,double precision),
    private.get_nearby_feed_impl(uuid,integer,integer,integer),public.get_nearby_feed(uuid,integer,integer,integer)
    from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.get_nearby_feed_impl(uuid,integer,integer,integer),public.get_nearby_feed(uuid,integer,integer,integer)to authenticated;
notify pgrst,'reload schema';
