-- Opt-in photo-only source. Existing workers and RPCs can run without this pilot.
create role yap_feed_vision_worker nologin;
grant yap_feed_vision_worker to authenticator;
grant usage on schema recsys,storage to yap_feed_vision_worker;
grant select on storage.objects to yap_feed_vision_worker;

create table recsys.vision_settings (
    singleton boolean primary key default true check (singleton),
    enabled boolean not null default false,
    space text not null unique check (space='8f6ef19478e47860edda9fd5d952f71c8e03d069f1f93099097620f538fac1cf')
);
insert into recsys.vision_settings (space) values ('8f6ef19478e47860edda9fd5d952f71c8e03d069f1f93099097620f538fac1cf');
alter table recsys.feed_snapshots add column vision_space text;
alter table feed.photo_uploads add column vision_pending_at timestamptz;
create index vision_deferred_photo on feed.photo_uploads(vision_pending_at,id) where vision_pending_at is not null;
create table recsys.vision_viewers (
    slot smallint primary key check (slot between 1 and 32),
    user_id uuid not null unique references public.profiles(id) on delete cascade,
    last_refresh_at timestamptz not null default '-infinity'
);
create table recsys.vision_jobs (
    photo_id uuid primary key references feed.photo_uploads(id) on delete cascade,
    source_sha text not null check (source_sha ~ '^[a-f0-9]{64}$'),
    space text not null references recsys.vision_settings(space),
    queued_at timestamptz not null default statement_timestamp(),
    available_at timestamptz not null default statement_timestamp(),
    backfill boolean not null default false,
    lease uuid,
    locked_until timestamptz,
    attempts integer not null default 0 check (attempts between 0 and 6),
    failed_at timestamptz,
    check ((lease is null) = (locked_until is null))
);
create index vision_job_due on recsys.vision_jobs (backfill, available_at, photo_id) where failed_at is null;
create index vision_job_lease on recsys.vision_jobs (locked_until) where locked_until is not null;
create index vision_job_age on recsys.vision_jobs (queued_at, photo_id);
create table recsys.vision_embeddings (
    photo_id uuid primary key references feed.photo_uploads(id) on delete cascade,
    post_id uuid not null references feed.posts(id) on delete cascade,
    source_sha text not null check (source_sha ~ '^[a-f0-9]{64}$'),
    space text not null references recsys.vision_settings(space),
    embedding extensions.vector(768) not null check (extensions.vector_norm(embedding) between .999 and 1.001),
    indexed_at timestamptz not null default statement_timestamp()
);
create index vision_embeddings_post on recsys.vision_embeddings (post_id);
create index vision_embeddings_recent on recsys.vision_embeddings (indexed_at,photo_id);
create index vision_embeddings_cosine on recsys.vision_embeddings using hnsw (embedding extensions.vector_cosine_ops);
alter table recsys.vision_settings enable row level security;
alter table recsys.vision_viewers enable row level security;
alter table recsys.vision_jobs enable row level security;
alter table recsys.vision_embeddings enable row level security;
revoke all on recsys.vision_settings,recsys.vision_viewers,recsys.vision_jobs,recsys.vision_embeddings
    from public,anon,authenticated,service_role,yap_feed_vision_worker,yap_recommendation_worker,yap_feed_media_worker;

create function private.vision_post_eligible(p feed.posts)
returns boolean language sql stable set search_path='' as $$
    select p.deleted_at is null and p.moderation_status='allowed' and p.audience='public'
      and p.created_at>statement_timestamp()-interval '7 days'
      and not private.is_account_globally_banned(p.author_id)
      and not private.is_account_pending_deletion(p.author_id)
$$;

-- A full outbox defers work durably on the source row without blocking publication.
create function private.enqueue_vision_photo()
returns trigger language plpgsql security definer set search_path='' as $$
declare model_space text;
begin
    if old.state='attached' and (new.state<>'attached' or new.sha256 is distinct from old.sha256 or
        new.image_path is distinct from old.image_path) then
        delete from recsys.vision_jobs where photo_id=old.id;
        delete from recsys.vision_embeddings where photo_id=old.id;
        update feed.photo_uploads set vision_pending_at=null where id=old.id and vision_pending_at is not null;
    end if;
    if new.state<>'attached' or (old.state='attached' and new.sha256 is not distinct from old.sha256 and
        new.image_path is not distinct from old.image_path) then return null; end if;
    select space into model_space from recsys.vision_settings where enabled;
    if model_space is null or not exists (
        select 1 from feed.posts p where p.id=new.draft_id and private.vision_post_eligible(p)
    ) then return null; end if;
    if pg_try_advisory_xact_lock(78563402064) and
       (select count(*) from recsys.vision_jobs where failed_at is null)<1024 then
        insert into recsys.vision_jobs(photo_id,source_sha,space) values(new.id,new.sha256,model_space)
        on conflict(photo_id) do nothing;
    else
        update feed.photo_uploads set vision_pending_at=statement_timestamp() where id=new.id;
    end if;
    return null;
end $$;
create trigger enqueue_vision_photo after update of state,sha256,image_path on feed.photo_uploads
    for each row execute function private.enqueue_vision_photo();

create function recsys.reconcile_vision_jobs()
returns integer language plpgsql security definer set search_path='' as $$
declare model_space text; room integer; cleared integer;
begin
    select space into model_space from recsys.vision_settings where enabled;
    if model_space is null or not pg_try_advisory_xact_lock(78563402064) then return 0; end if;
    select 1024-count(*) into room from recsys.vision_jobs where failed_at is null;
    if room<1 then return 0; end if;
    with pending as materialized(
        select a.id,a.draft_id,a.sha256,a.state,a.vision_pending_at from feed.photo_uploads a
        where a.vision_pending_at is not null
        order by a.vision_pending_at,a.id limit least(room,32) for update skip locked
    ), queued as(
        insert into recsys.vision_jobs(photo_id,source_sha,space,queued_at)
        select a.id,a.sha256,model_space,a.vision_pending_at from pending a
        join feed.posts p on p.id=a.draft_id where a.state='attached' and private.vision_post_eligible(p)
        on conflict(photo_id) do nothing
    )
    update feed.photo_uploads a set vision_pending_at=null from pending p where p.id=a.id;
    get diagnostics cleared=row_count;
    return cleared;
end $$;

create function recsys.vision_contract()
returns jsonb language sql security definer stable set search_path='' as $$
    select jsonb_build_object('space',space,'dimension',768,'enabled',enabled) from recsys.vision_settings
$$;

create function private.vision_storage_readable(object_name text)
returns boolean language sql security definer stable set search_path='' as $$
    select exists (
        select 1 from feed.photo_uploads u join recsys.vision_jobs j on j.photo_id=u.id and j.source_sha=u.sha256
        join feed.posts p on p.id=u.draft_id join recsys.vision_settings s on s.space=j.space
        where u.image_path=object_name and u.state='attached' and s.enabled and j.failed_at is null
          and j.locked_until>statement_timestamp() and private.vision_post_eligible(p)
    )
$$;
create policy "Vision reads leased prepared images" on storage.objects for select to yap_feed_vision_worker
    using(bucket_id='feed-media' and private.vision_storage_readable(name));

create function recsys.claim_vision_photo(requested_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job recsys.vision_jobs%rowtype; result jsonb;
begin
    if requested_lease is null then raise exception using errcode='22023',message='invalid_vision_lease'; end if;
    -- Reap expired/exhausted jobs in a bounded batch, including idle/outage recovery.
    with stale as materialized(
        select j.photo_id from recsys.vision_jobs j
        where j.failed_at is null and j.attempts=6 and j.locked_until<=statement_timestamp()
        order by j.available_at,j.photo_id limit 32 for update skip locked
    )
    update recsys.vision_jobs j set failed_at=statement_timestamp(),lease=null,locked_until=null
    from stale where j.photo_id=stale.photo_id;
    if not exists(select 1 from recsys.vision_settings where enabled)
       or not pg_try_advisory_xact_lock(78563402065)
       or exists(select 1 from recsys.vision_jobs where locked_until>statement_timestamp())
    then return null; end if;
    select * into job from recsys.vision_jobs j
    where j.failed_at is null and j.attempts<6 and j.available_at<=statement_timestamp()
      and (j.lease is null or j.locked_until<=statement_timestamp())
    order by j.backfill,j.available_at,j.photo_id limit 1 for update skip locked;
    if not found then return null; end if;
    select jsonb_build_object('id',u.id,'sha256',u.sha256,'path',u.image_path,'bytes',u.image_bytes,
        'space',job.space,'lease',requested_lease,'queued_at',job.queued_at)
    into result from feed.photo_uploads u join feed.posts p on p.id=u.draft_id
    where u.id=job.photo_id and u.state='attached' and u.sha256=job.source_sha and private.vision_post_eligible(p);
    if result is null then
        delete from recsys.vision_jobs where photo_id=job.photo_id;
        return null;
    end if;
    update recsys.vision_jobs set lease=requested_lease,locked_until=statement_timestamp()+interval '45 seconds',
        attempts=attempts+1 where photo_id=job.photo_id;
    return result;
end $$;

create function recsys.retry_vision_photo(photo uuid, requested_lease uuid, terminal boolean)
returns void language sql security definer set search_path='' as $$
    update recsys.vision_jobs
    set lease=null,locked_until=null,available_at=statement_timestamp()+make_interval(secs=>power(2,attempts)::int),
      failed_at=case when terminal or attempts=6 then statement_timestamp() end
    where photo_id=photo and lease=requested_lease and locked_until>statement_timestamp()
$$;

create function recsys.complete_vision_photo(photo uuid, requested_lease uuid, expected_sha text,
                                             expected_space text, value extensions.vector)
returns boolean language plpgsql security definer set search_path='' as $$
declare item feed.photo_uploads%rowtype; post feed.posts%rowtype; job recsys.vision_jobs%rowtype;
begin
    if expected_sha is null or expected_space is null or value is null or extensions.vector_dims(value)<>768
       or extensions.vector_norm(value) not between .999 and 1.001 then
        raise exception using errcode='22023',message='invalid_vision_result';
    end if;
    select p.* into post from feed.posts p join feed.photo_uploads u on u.draft_id=p.id
      where u.id=photo for share of p;
    select * into item from feed.photo_uploads where id=photo for share;
    select * into job from recsys.vision_jobs where photo_id=photo and lease=requested_lease
      and locked_until>clock_timestamp() for update;
    if not found then return false; end if;
    if job.source_sha is distinct from expected_sha or job.space is distinct from expected_space then return false; end if;
    if item.state is distinct from 'attached' or item.sha256 is distinct from job.source_sha
        or not coalesce(private.vision_post_eligible(post),false) then
        delete from recsys.vision_jobs where photo_id=photo;
        return false;
    end if;
    if not exists(select 1 from recsys.vision_settings where enabled and space=job.space) then
        update recsys.vision_jobs set lease=null,locked_until=null,attempts=greatest(0,attempts-1) where photo_id=photo;
        return false;
    end if;
    insert into recsys.vision_embeddings(photo_id,post_id,source_sha,space,embedding)
    values(photo,post.id,job.source_sha,job.space,value)
    on conflict(photo_id) do update set source_sha=excluded.source_sha,space=excluded.space,
      embedding=excluded.embedding,indexed_at=statement_timestamp();
    delete from recsys.vision_jobs where photo_id=photo;
    return true;
end $$;

-- Only the operator can call backfill. Source keyset progress is independent of
-- queue depth; when saturated the caller keeps the previous cursor.
create function recsys.enqueue_vision_backfill(after_photo uuid, requested_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare model_space text; room integer; scanned integer; added integer; last_photo uuid;
begin
    if requested_limit is null or requested_limit not between 1 and 128 then
      raise exception using errcode='22023',message='invalid_vision_backfill_limit'; end if;
    select space into model_space from recsys.vision_settings where enabled;
    if model_space is null or not pg_try_advisory_xact_lock(78563402064) then
      return jsonb_build_object('scanned',0,'enqueued',0,'after_photo',after_photo,'paused',true); end if;
    select 1024-count(*) into room from recsys.vision_jobs where failed_at is null;
    if room<1 then return jsonb_build_object('scanned',0,'enqueued',0,'after_photo',after_photo,'paused',true); end if;
    with source as materialized(
      select u.id,u.draft_id,u.sha256 from feed.photo_uploads u
      where u.id>coalesce(after_photo,'00000000-0000-0000-0000-000000000000'::uuid)
      order by u.id limit least(room,requested_limit)
    ), queued as (
      insert into recsys.vision_jobs(photo_id,source_sha,space,backfill)
      select u.id,u.sha256,model_space,true from source u join feed.photo_uploads pht on pht.id=u.id
      join feed.posts p on p.id=u.draft_id where pht.state='attached' and private.vision_post_eligible(p)
        and not exists(select 1 from recsys.vision_embeddings e where e.photo_id=u.id and e.source_sha=u.sha256)
      on conflict(photo_id) do nothing returning photo_id
    )
    select (select count(*) from source),(select count(*) from queued),(select id from source order by id desc limit 1)
      into scanned,added,last_photo;
    return jsonb_build_object('scanned',scanned,'enqueued',added,'after_photo',last_photo,'paused',false);
end $$;

-- A separate, bounded visual profile uses the same authoritative actions and
-- reset epoch. It lives for one preparation pass; old photos are checked live.
create function recsys.load_vision_candidates(viewer uuid, requested_lease uuid, requested_epoch integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
    perform private.require_refresh_lease(viewer,requested_lease);
    if not exists(select 1 from recsys.vision_settings where enabled)
       or not exists(select 1 from recsys.vision_viewers where user_id=viewer)
       or not exists(select 1 from recsys.user_states where user_id=viewer and epoch=requested_epoch)
    then return null; end if;
    with signals as (
        (select l.post_id,l.post_version,l.created_at at,2.0::float8 weight from feed.post_likes l
         where l.user_id=viewer and l.epoch=requested_epoch and l.created_at>statement_timestamp()-interval '7 days'
         order by l.created_at desc,l.post_id limit 24)
        union all
        (select e.post_id,e.post_version,e.engaged_at,1.0 from recsys.daily_exposures e
         where e.user_id=viewer and e.epoch=requested_epoch and (e.opened or e.active_ms>=5000)
           and e.engaged_at>statement_timestamp()-interval '7 days' order by e.last_seen_at desc,e.post_id limit 24)
        union all
        (select f.post_id,f.post_version,f.created_at,1.5 from recsys.social_feedback f
         where f.user_id=viewer and f.epoch=requested_epoch and f.created_at>statement_timestamp()-interval '7 days'
           and private.social_feedback_allowed(viewer,f) order by f.created_at desc,f.post_id limit 24)
        union all
        (select h.post_id,h.post_version,h.created_at,-3.0 from recsys.semantic_suppressions h
         where h.user_id=viewer and h.epoch=requested_epoch order by h.created_at desc,h.post_id limit 24)
    ), recent as materialized (
        select post_id,post_version,max(at) at,case when min(weight)<0 then -3.0 else max(weight) end weight
        from signals group by post_id,post_version order by max(at) desc,post_id limit 24
    ), evidence as materialized (
        select g.post_id,g.post_version,g.at,g.weight,extensions.l2_normalize(images.embedding) embedding
        from recent g join feed.posts p on p.id=g.post_id and p.version=g.post_version
        cross join lateral(
            select extensions.avg(u.embedding) embedding from (
                select distinct on(e.source_sha) e.embedding from recsys.vision_embeddings e
                join feed.photo_uploads a on a.id=e.photo_id and a.state='attached' and a.sha256=e.source_sha
                where e.post_id=p.id order by e.source_sha,e.photo_id limit 3
            )u
        )images
        where p.author_id<>viewer and private.vision_post_eligible(p) and private.feed_post_accessible(viewer,p)
          and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
          and extensions.vector_norm(images.embedding)>0
    ), profile as materialized (
        select extensions.l2_normalize(extensions.avg(embedding)) filter_embedding, weight<0 negative
        from evidence group by weight<0
    ), nearest as materialized (
        select match.* from profile t cross join lateral(
            select e.photo_id,e.post_id,e.source_sha,e.embedding,
                e.embedding operator(extensions.<=>) t.filter_embedding distance
            from recsys.vision_embeddings e
            order by e.embedding operator(extensions.<=>) t.filter_embedding limit 96
        )match where not t.negative and extensions.vector_norm(t.filter_embedding)>0
    ), scored as materialized (
        -- Similarity 0.62 is near the corpus background p95; 0.79 is
        -- near the within-topic p75. Keep the resulting visual score bounded.
        select n.post_id,max(greatest(0,least(1,(.38-n.distance)/.17))
             * (1-coalesce((select greatest(0,least(1,(.38-(n.embedding operator(extensions.<=>) t.filter_embedding))/.17))
                from profile t where t.negative and extensions.vector_norm(t.filter_embedding)>0),0))) similarity
        from nearest n join feed.photo_uploads u on u.id=n.photo_id and u.state='attached' and u.sha256=n.source_sha
        group by n.post_id
    ), items as (
        select p.id,p.author_id,p.version,p.created_at,s.similarity,
          coalesce(st.impressions,0) impressions,coalesce(st.likes,0) likes,coalesce(st.reposts,0) reposts,
          coalesce(reach.impressions,0) author_impressions,coalesce(reach.viewers,0) author_viewers,
          exists(select 1 from recsys.daily_exposures x where x.user_id=viewer and x.post_id=p.id
            and x.last_seen_at>statement_timestamp()-interval '24 hours') seen
        from scored s join feed.posts p on p.id=s.post_id
        left join recsys.post_statistics st on st.post_id=p.id
        left join recsys.author_statistics reach on reach.author_id=p.author_id
        where s.similarity>0 and p.text='' and p.author_id<>viewer
          and private.vision_post_eligible(p) and private.feed_post_accessible(viewer,p)
          and not exists(select 1 from evidence e where e.post_id=p.id)
          and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
          and not exists(select 1 from recsys.semantic_suppressions h where h.user_id=viewer and h.post_id=p.id)
        order by s.similarity desc,p.id limit 32
    )
    select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i) order by i.similarity desc,i.id) from items i),'[]'),
        'evidence',coalesce((select jsonb_agg(jsonb_build_object('post_id',e.post_id,'post_version',e.post_version) order by e.post_id) from evidence e),'[]'),
        'fence',coalesce((select jsonb_agg(jsonb_build_object('photo_id',v.photo_id,'sha',v.source_sha) order by v.photo_id)
            from recsys.vision_embeddings v
            where v.post_id in(select e.post_id from evidence e union select i.id from items i)),'[]'))
    into result;
    return result;
end $$;

-- Existing readers continue to use the ordinary, live-authorized snapshots.
-- Stamp a distinct policy so later offline exports can distinguish this pilot.
create function recsys.publish_vision_recommendations(viewer uuid, requested_lease uuid, result jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare accepted boolean; model_space text;
begin
    if result is null or jsonb_typeof(result->'vision_fence') is distinct from 'array'
       or jsonb_array_length(result->'vision_fence') not between 1 and 168 then
        raise exception using errcode='22023',message='invalid_vision_fence';
    end if;
    select space into model_space from recsys.vision_settings where enabled for share;
    if not found then raise exception using errcode='40001',message='vision_pilot_disabled'; end if;
    perform 1 from recsys.vision_viewers where user_id=viewer for share;
    if not found then raise exception using errcode='40001',message='vision_viewer_removed'; end if;
    accepted:=recsys.publish_recommendations(viewer,requested_lease,result);
    if accepted then
        -- The surrounding transaction rolls back the base publisher when a
        -- derivative used by the profile or candidate pool has been replaced.
        perform u.id from jsonb_array_elements(result->'vision_fence') f
          join feed.photo_uploads u on u.id=(f->>'photo_id')::uuid order by u.id for share of u;
        if exists(select 1 from jsonb_array_elements(result->'vision_fence') f
            left join feed.photo_uploads u on u.id=(f->>'photo_id')::uuid
            left join feed.posts p on p.id=u.draft_id
            left join recsys.vision_embeddings e on e.photo_id=u.id and e.source_sha=u.sha256
            where u.state is distinct from 'attached' or u.sha256 is distinct from f->>'sha'
              or e.photo_id is null or not coalesce(private.vision_post_eligible(p),false)
              or not coalesce(private.feed_post_accessible(viewer,p),false)) then
            raise exception using errcode='40001',message='vision_source_changed';
        end if;
        if exists(select 1 from jsonb_array_elements(result->'items') i
            left join feed.posts p on p.id=(i->>'post_id')::uuid
            where i->'sources' ? 'vision'
              and (p.id is null or p.text<>'' or p.version<>(i->>'post_version')::integer)) then
            raise exception using errcode='40001',message='vision_candidate_changed';
        end if;
        update recsys.feed_snapshots s set policy_version='hybrid-v2-vision-siglip2-v1',vision_space=model_space
        from recsys.user_states u where u.user_id=viewer and s.id=u.current_snapshot;
    end if;
    return accepted;
end $$;

create function recsys.cleanup_vision_pilot()
returns void language plpgsql security definer set search_path='' as $$
begin
    with stale as materialized(
        select j.photo_id from recsys.vision_jobs j where j.queued_at<statement_timestamp()-interval '7 days'
        order by j.queued_at,j.photo_id limit 128 for update skip locked
    )
    delete from recsys.vision_jobs j using stale where j.photo_id=stale.photo_id;
    with stale as materialized(
        select e.photo_id from recsys.vision_embeddings e where e.indexed_at<statement_timestamp()-interval '7 days'
        order by e.indexed_at,e.photo_id limit 128 for update skip locked
    )
    delete from recsys.vision_embeddings e using stale where e.photo_id=stale.photo_id;
end $$;

create function recsys.refresh_vision_pilot()
returns integer language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
    if not exists(select 1 from recsys.vision_settings where enabled) then return 0; end if;
    with ready as materialized(
        select v.user_id from recsys.vision_viewers v
        where v.last_refresh_at<statement_timestamp()-interval '10 seconds' and exists(
          select 1 from recsys.vision_embeddings e where e.indexed_at>v.last_refresh_at
        ) order by v.user_id for update of v skip locked
    ), touched as(
        update recsys.vision_viewers v set last_refresh_at=statement_timestamp() from ready
        where v.user_id=ready.user_id returning v.user_id
    ), revisions as(
        update recsys.user_states u set revision=u.revision+1 from touched
        where u.user_id=touched.user_id returning u.user_id,u.revision
    )
    select count(*) into changed from (
        select private.queue_recommendation_refresh(r.user_id,r.revision,false) from revisions r
    ) scheduled;
    return changed;
end $$;

revoke all on function private.vision_post_eligible(feed.posts),private.enqueue_vision_photo(),
    private.vision_storage_readable(text),recsys.vision_contract(),recsys.claim_vision_photo(uuid),
    recsys.retry_vision_photo(uuid,uuid,boolean),recsys.complete_vision_photo(uuid,uuid,text,text,extensions.vector),
    recsys.enqueue_vision_backfill(uuid,integer),recsys.refresh_vision_pilot(),recsys.cleanup_vision_pilot(),
    recsys.reconcile_vision_jobs(),
    recsys.load_vision_candidates(uuid,uuid,integer),recsys.publish_vision_recommendations(uuid,uuid,jsonb)
    from public,anon,authenticated,service_role,yap_feed_media_worker,yap_recommendation_worker,yap_feed_vision_worker;
grant usage on schema extensions to yap_feed_vision_worker;
grant execute on function private.vision_storage_readable(text),recsys.vision_contract(),
    recsys.claim_vision_photo(uuid),recsys.retry_vision_photo(uuid,uuid,boolean),
    recsys.complete_vision_photo(uuid,uuid,text,text,extensions.vector),recsys.refresh_vision_pilot(),
    recsys.cleanup_vision_pilot(),recsys.reconcile_vision_jobs() to yap_feed_vision_worker;
grant execute on function recsys.load_vision_candidates(uuid,uuid,integer),
    recsys.publish_vision_recommendations(uuid,uuid,jsonb) to yap_recommendation_worker;
