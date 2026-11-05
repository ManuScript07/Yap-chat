-- Bounded asynchronous preparation. No client-visible worker endpoint.
alter table recsys.index_jobs add column job_kind text not null default 'live'
    check (job_kind in ('live', 'backfill')), add column claimed_at timestamptz;
create index recsys_index_jobs_lane_idx on recsys.index_jobs(model,job_kind,available_at,id)
    where done_at is null and attempts<8;
alter table recsys.refresh_jobs add column priority smallint not null default 0 check(priority in(0,1)),
    add column requested_at timestamptz not null default statement_timestamp(),
    add column claimed_at timestamptz;
create index recsys_refresh_priority_idx on recsys.refresh_jobs(priority,available_at,user_id)where attempts<8;
alter table recsys.feed_snapshots add column feature_version text not null default 'hybrid-v1',
    add column policy_version text not null default 'personalized-v1',
    add column embedding_space text not null default 'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query',
    add column queued_at timestamptz, add column claimed_at timestamptz;
create index recsys_snapshots_created_idx on recsys.feed_snapshots(created_at desc,id);
alter table recsys.deliveries add column feature_version text not null default 'none',
    add column policy_version text not null default 'direct-v1',
    add column embedding_space text not null default '';
update recsys.deliveries set embedding_space=embedding_model,policy_version=model;
update recsys.deliveries d set feature_version=s.feature_version,policy_version=s.policy_version,
    embedding_space=s.embedding_space from recsys.feed_snapshots s where d.snapshot_id=s.id;

create or replace function private.queue_recommendation_refresh(viewer uuid, version bigint, immediate boolean default false)
returns void language sql security definer set search_path='' as $$
    insert into recsys.refresh_jobs as j(user_id,target_revision,priority,available_at)
    select viewer,version,case when version>1 and version>s.processed_revision then 0 else 1 end,
        statement_timestamp()+case when immediate then interval '0 seconds'else interval '1 second'end
    from recsys.user_states s where s.user_id=viewer
    on conflict(user_id)do update set target_revision=greatest(j.target_revision,excluded.target_revision),
        priority=least(j.priority,excluded.priority),
        requested_at=case when excluded.priority<j.priority then excluded.requested_at else j.requested_at end,
        available_at=least(j.available_at,excluded.available_at),
        attempts=case when excluded.target_revision>j.target_revision then 0 else j.attempts end;
$$;

create function recsys.claim_refresh_job(requested_lease uuid,requested_priority integer)
returns table(user_id uuid,lease uuid)language plpgsql security definer set search_path='' as $$
begin
    if requested_lease is null or(requested_priority is not null and requested_priority not in(0,1))then
        raise exception using errcode='22023',message='invalid_refresh_claim';end if;
    return query with candidate as(
        select j.user_id from recsys.refresh_jobs j join recsys.user_states s on s.user_id=j.user_id
        where j.available_at<=statement_timestamp()and j.attempts<8
          and(j.locked_until is null or j.locked_until<=statement_timestamp())
          and(requested_priority is null or j.priority=requested_priority)
          and s.active_until>statement_timestamp()
        order by j.priority,j.available_at,j.user_id for update of j skip locked limit 1
    )update recsys.refresh_jobs j set lease=requested_lease,claimed_at=statement_timestamp(),
        locked_until=statement_timestamp()+interval '60 seconds',attempts=j.attempts+1
        from candidate c where j.user_id=c.user_id returning j.user_id,j.lease;
end $$;
create or replace function recsys.claim_refresh_job(requested_lease uuid)
returns table(user_id uuid,lease uuid)language sql security definer set search_path='' as $$
    select * from recsys.claim_refresh_job(requested_lease,null);
$$;

create function recsys.claim_index_batch(requested_lease uuid,requested_model text,requested_kind text,requested_limit integer)
returns table(id bigint,lease uuid,post_id uuid,post_version integer,text text)
language plpgsql security definer set search_path='' as $$
begin
    if requested_lease is null or requested_model is null or requested_kind is null
        or requested_kind not in('live','backfill')or requested_limit is null or requested_limit not between 1 and 8 then
        raise exception using errcode='22023',message='invalid_index_batch';end if;
    return query with candidate as(
        select j.id from recsys.index_jobs j where j.model=requested_model and j.job_kind=requested_kind
          and j.done_at is null and j.attempts<8 and j.available_at<=statement_timestamp()
          and(j.locked_until is null or j.locked_until<=statement_timestamp())
        order by j.available_at,j.id for update skip locked limit requested_limit
    ),claimed as(
        update recsys.index_jobs j set lease=requested_lease,claimed_at=statement_timestamp(),
          locked_until=statement_timestamp()+interval '60 seconds',attempts=j.attempts+1
          from candidate c where j.id=c.id returning j.*
    )select j.id,j.lease,j.post_id,j.post_version,
        case when p.version=j.post_version and p.deleted_at is null and p.moderation_status='allowed'
          and not private.is_account_globally_banned(p.author_id)and not private.is_account_pending_deletion(p.author_id)
        then p.text else ''end
        from claimed j join feed.posts p on p.id=j.post_id order by p.id,j.id;
end $$;

create function recsys.complete_index_batch(requested_results jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare item jsonb;accepted integer:=0;
begin
    if requested_results is null or jsonb_typeof(requested_results)<>'array'
        or jsonb_array_length(requested_results)not between 1 and 8 or octet_length(requested_results::text)>131072 then
        raise exception using errcode='22023',message='invalid_index_batch';end if;
    -- Same source -> job order as ordinary completion, globally ordered for a batch.
    perform p.id from feed.posts p join recsys.index_jobs j on j.post_id=p.id
        join jsonb_array_elements(requested_results)r on j.id=(r->>'id')::bigint
        order by p.id,j.id for share of p;
    for item in select r from jsonb_array_elements(requested_results)r
        join recsys.index_jobs j on j.id=(r->>'id')::bigint order by j.post_id,j.id
    loop
        if recsys.complete_index_job((item->>'id')::bigint,(item->>'lease')::uuid,
            (item->>'vector')::extensions.vector)then accepted:=accepted+1;end if;
    end loop;
    return accepted;
end $$;

create function recsys.enqueue_index_backfill(after_post uuid,requested_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare last_id uuid;scanned integer;added integer;
begin
    if requested_limit is null or requested_limit not between 1 and 500 then
        raise exception using errcode='22023',message='invalid_backfill_limit';end if;
    with source as materialized(
        select p.id,p.version from feed.posts p where(after_post is null or p.id>after_post)
          and p.text<>''and p.deleted_at is null and p.moderation_status='allowed'
        order by p.id limit requested_limit
    ),created as(
        insert into recsys.index_jobs(post_id,post_version,model,job_kind)
        select p.id,p.version,'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query','backfill'
        from source p where not exists(select 1 from recsys.post_embeddings e where e.post_id=p.id and e.post_version=p.version
          and e.model='intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')
        on conflict(post_id,post_version,model)do update set job_kind='backfill',done_at=null,
          attempts=0,available_at=statement_timestamp(),lease=null,locked_until=null,last_error=null
          where recsys.index_jobs.done_at is not null returning 1
    )select(select count(*)from source),(select id from source order by id desc limit 1),(select count(*)from created)
      into scanned,last_id,added;
    return jsonb_build_object('scanned',scanned,'enqueued',added,'after_post',last_id,'has_more',scanned=requested_limit);
end $$;

-- Coverage is actual qualified, external attention across the author, rather
-- than resetting discovery eligibility whenever an established author posts.
create table recsys.author_statistics(
    author_id uuid primary key references public.profiles(id)on delete cascade,
    impressions bigint not null default 0 check(impressions>=0),
    viewers bigint not null default 0 check(viewers>=0)
);
create table recsys.author_viewers(
    author_id uuid not null references public.profiles(id)on delete cascade,
    viewer_id uuid not null references public.profiles(id)on delete cascade,
    primary key(author_id,viewer_id)
);
create index recsys_author_viewers_reader_idx on recsys.author_viewers(viewer_id,author_id);
insert into recsys.author_statistics(author_id)select id from public.profiles;
insert into recsys.author_viewers(author_id,viewer_id)
    select distinct p.author_id,e.user_id from recsys.daily_exposures e join feed.posts p on p.id=e.post_id
    where p.author_id<>e.user_id on conflict do nothing;
with counts as(select author_id,count(*)n from recsys.author_viewers group by author_id)
update recsys.author_statistics s set viewers=c.n from counts c where c.author_id=s.author_id;
with counts as(select p.author_id,count(*)n from recsys.daily_exposures e join feed.posts p on p.id=e.post_id
    where e.user_id<>p.author_id group by p.author_id)
update recsys.author_statistics s set impressions=c.n from counts c where c.author_id=s.author_id;
alter table recsys.author_statistics enable row level security;
alter table recsys.author_viewers enable row level security;
revoke all on recsys.author_statistics,recsys.author_viewers from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;

create function private.create_author_statistics()
returns trigger language plpgsql security definer set search_path='' as $$
begin insert into recsys.author_statistics(author_id)values(new.id)on conflict do nothing;return null;end $$;
create trigger feed_author_statistics_created after insert on public.profiles
    for each row execute function private.create_author_statistics();
create function private.record_author_reach(target_author uuid,viewer uuid)
returns void language plpgsql security definer set search_path='' as $$
declare inserted integer;
begin
    if target_author=viewer then return;end if;
    insert into recsys.author_viewers(author_id,viewer_id)values(target_author,viewer)on conflict do nothing;
    get diagnostics inserted=row_count;
    update recsys.author_statistics set impressions=impressions+1,viewers=viewers+inserted where author_id=target_author;
end $$;

create function private.stamp_feed_delivery_versions()
returns trigger language plpgsql security definer set search_path='' as $$
begin
    if new.snapshot_id is not null then
        select s.feature_version,s.policy_version,s.embedding_space
          into new.feature_version,new.policy_version,new.embedding_space from recsys.feed_snapshots s where s.id=new.snapshot_id;
    else new.feature_version:='none';new.policy_version:=new.model;new.embedding_space:=new.embedding_model;end if;
    return new;
end $$;
create trigger feed_delivery_versions before insert on recsys.deliveries
    for each row execute function private.stamp_feed_delivery_versions();

create or replace function recsys.personalization_contract()
returns jsonb language sql stable set search_path='' as $$
    select jsonb_build_object('version',2,'feature_version','feed-features-v2','policy_version','hybrid-v2',
        'model','personalized-v2','embedding_space',
        'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query',
        'max_candidates',1200,'max_items',200,'max_batch',8);
$$;

create or replace function recsys.publish_recommendations(viewer uuid, requested_lease uuid, requested_result jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare config jsonb:=recsys.personalization_contract();s recsys.user_states%rowtype; j recsys.refresh_jobs%rowtype; snapshot uuid:=extensions.gen_random_uuid();
  input_epoch integer:=(requested_result->>'epoch')::integer; input_revision bigint:=(requested_result->>'revision')::bigint;
  input_at timestamptz:=(requested_result->>'at')::timestamptz; model_name text:=config->>'embedding_space';
begin
  if requested_result is null or jsonb_typeof(requested_result)<>'object' or octet_length(requested_result::text)>262144
    or not(requested_result ?& array['epoch','revision','at','feature_version','profile','items','evidence','needs_embeddings']) then
    raise exception using errcode='22023',message='invalid_recommendation_result'; end if;
  select * into s from recsys.user_states where user_id=viewer for update;
  if not found then return false; end if;
  select * into j from recsys.refresh_jobs where user_id=viewer and lease=requested_lease and locked_until>clock_timestamp() for update;
  if not found then return false; end if;
  if s.epoch<>input_epoch or input_revision<s.processed_revision then
    update recsys.refresh_jobs set lease=null,locked_until=null,available_at=statement_timestamp(),attempts=0 where user_id=viewer;
    return false;
  end if;
  if private.is_account_globally_banned(viewer) or private.is_account_pending_deletion(viewer) then
    delete from recsys.refresh_jobs where user_id=viewer;return false;
  end if;
  if input_revision is null or input_revision>s.revision or input_at is null
    or requested_result->>'feature_version' is distinct from(config->>'feature_version')
    or requested_result->>'policy_version' is distinct from(config->>'policy_version')
    or requested_result->>'embedding_space' is distinct from model_name
    or jsonb_typeof(requested_result->'profile')<>'array' or jsonb_array_length(requested_result->'profile')>8
    or jsonb_typeof(requested_result->'items')<>'array' or jsonb_array_length(requested_result->'items')>200 then
    raise exception using errcode='22023',message='invalid_recommendation_result';
  end if;
  -- A text edit/deletion between evidence loading and publication must not
  -- publish a profile derived from an obsolete version of that text.
  perform p.id from feed.posts p join jsonb_array_elements(requested_result->'evidence')e on p.id=(e->>'post_id')::uuid
    order by p.id for share of p;
  if exists(select 1 from jsonb_array_elements(requested_result->'evidence')e
    left join feed.posts p on p.id=(e->>'post_id')::uuid
    where p.id is null or p.version<>(e->>'post_version')::integer or p.deleted_at is not null or p.moderation_status<>'allowed'
      or not private.feed_post_accessible(viewer,p)) then
    update recsys.refresh_jobs set lease=null,locked_until=null,available_at=statement_timestamp(),attempts=0 where user_id=viewer;
    return false;
  end if;
  delete from recsys.interest_clusters where user_id=viewer;
  insert into recsys.interest_clusters(user_id,epoch,cluster,model,negative,weight,embedding,updated_at)
    select viewer,input_epoch,(c.ordinality-1)::integer,model_name,(c.value->>'negative')::boolean,
      (c.value->>'weight')::float8,(c.value->>'vector')::extensions.vector,input_at
    from jsonb_array_elements(requested_result->'profile')with ordinality c;
  -- Reuse an unexpired pool when no user evidence changed and its order and
  -- explanation stayed identical. Preserve the original feature timestamp:
  -- training must know which cached features actually produced the delivery.
  select old.id into snapshot from recsys.feed_snapshots old where old.id=s.current_snapshot and old.user_id=viewer
    and old.epoch=input_epoch and old.model=config->>'model'and old.feature_version=config->>'feature_version'and old.policy_version=config->>'policy_version'and old.embedding_space=model_name and old.expires_at>statement_timestamp()+interval '1 minute'
    and s.processed_revision=input_revision and s.profile_complete and not coalesce((requested_result->>'needs_embeddings')::boolean,false)
    and coalesce((select jsonb_agg(jsonb_build_object('post_id',i.post_id,'post_version',i.post_version,'reasons',i.reasons,'sources',i.sources)order by i.position)
      from recsys.feed_snapshot_items i where i.snapshot_id=old.id),'[]')=
      (select coalesce(jsonb_agg(item-'features'-'score'),'[]')from jsonb_array_elements(requested_result->'items')item);
  if not found then
    snapshot:=extensions.gen_random_uuid();
    insert into recsys.feed_snapshots(id,user_id,epoch,revision,model,embedding_model,features_at,feature_version,policy_version,embedding_space,queued_at,claimed_at)
      values(snapshot,viewer,input_epoch,input_revision,config->>'model',model_name,input_at,config->>'feature_version',config->>'policy_version',model_name,j.requested_at,j.claimed_at);
    insert into recsys.feed_snapshot_items(snapshot_id,position,post_id,post_version,features,score,reasons,sources)
    select snapshot,(item.ordinality-1)::integer,(item.value->>'post_id')::uuid,(item.value->>'post_version')::integer,
      array(select value::float8 from jsonb_array_elements_text(item.value->'features')),
      (item.value->>'score')::float8,array(select jsonb_array_elements_text(item.value->'reasons')),
      array(select jsonb_array_elements_text(item.value->'sources'))
    from jsonb_array_elements(requested_result->'items')with ordinality item
    join feed.posts p on p.id=(item.value->>'post_id')::uuid;
  end if;
  update recsys.user_states set current_snapshot=snapshot,prepared_at=statement_timestamp(),processed_revision=input_revision,
    profile_complete=not coalesce((requested_result->>'needs_embeddings')::boolean,false)where user_id=viewer;
  if j.target_revision>input_revision or coalesce((requested_result->>'needs_embeddings')::boolean,false) then
    update recsys.refresh_jobs set lease=null,locked_until=null,attempts=0,last_error=null,
      priority=case when j.target_revision>input_revision then 0 else j.priority end,requested_at=statement_timestamp(),
      available_at=statement_timestamp()+case when j.target_revision>input_revision then interval '1 second' else interval '3 seconds' end where user_id=viewer;
  else delete from recsys.refresh_jobs where user_id=viewer; end if;
  return true;
end $$;

create or replace function private.record_feed_events_impl(requested_events jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; d recsys.deliveries%rowtype; p feed.posts%rowtype;
  event jsonb; event_id uuid; receipt uuid; kind text; previous jsonb; visible integer; fraction double precision; active integer;
  accepted integer:=0; duplicates integer:=0; stale integer:=0; first_view boolean; elapsed_ms bigint;
  today date:=(statement_timestamp() at time zone 'UTC')::date;
begin
  perform private.require_active_account();
  if requested_events is null or jsonb_typeof(requested_events)<>'array' or jsonb_array_length(requested_events) not between 1 and 100
    or octet_length(requested_events::text)>65536 then raise exception using errcode='22023',message='invalid_event_batch'; end if;
  perform profile.id from public.profiles profile where profile.id=auth.uid()or profile.id in(
    select source_post.author_id from jsonb_array_elements(requested_events)e join recsys.deliveries owned_delivery
      on owned_delivery.id=(e->>'delivery_id')::uuid and owned_delivery.user_id=auth.uid()join feed.posts source_post on source_post.id=owned_delivery.post_id
  )order by profile.id for key share;
  perform private.require_social_account();
  perform private.consume_feed_quota('feed_events');
  s:=private.lock_recommendation_user(auth.uid());
  perform stats.author_id from recsys.author_statistics stats where stats.author_id in(
    select source_post.author_id from jsonb_array_elements(requested_events)e join recsys.deliveries owned_delivery
      on owned_delivery.id=(e->>'delivery_id')::uuid and owned_delivery.user_id=auth.uid()join feed.posts source_post on source_post.id=owned_delivery.post_id
  )order by stats.author_id for update;

  for event in select value from jsonb_array_elements(requested_events) loop
    if jsonb_typeof(event)<>'object' or exists(select 1 from jsonb_object_keys(event) k
      where k not in ('event_id','delivery_id','kind','visible_ms','visible_fraction','active_ms')) then
      raise exception using errcode='22023',message='invalid_feed_event';
    end if;
    event_id:=(event->>'event_id')::uuid; receipt:=(event->>'delivery_id')::uuid; kind:=event->>'kind';
    if event_id is null or receipt is null or kind is null or kind not in ('impression','dwell','open_post') then
      raise exception using errcode='22023',message='invalid_feed_event';
    end if;
    select payload into previous from recsys.telemetry_events where user_id=auth.uid() and id=event_id;
    if found then
      if previous<>event then raise exception using errcode='23505',message='event_id_conflict'; end if;
      duplicates:=duplicates+1; continue;
    end if;
    select * into d from recsys.deliveries where id=receipt and user_id=auth.uid() for update;
    if not found then raise exception using errcode='22023',message='invalid_delivery'; end if;
    select * into p from feed.posts where id=d.post_id;
    if not found or d.valid_until<=statement_timestamp() or d.epoch<>s.epoch or p.version<>d.post_version or p.deleted_at is not null or p.moderation_status<>'allowed'
      or not private.feed_post_accessible(auth.uid(),p) then stale:=stale+1; continue; end if;
    elapsed_ms:=greatest(0,floor(extract(epoch from (statement_timestamp()-d.delivered_at))*1000)::bigint);
    today:=(statement_timestamp()at time zone 'UTC')::date;
    if kind='impression' then
      visible:=(event->>'visible_ms')::integer; fraction:=(event->>'visible_fraction')::double precision;
      if visible is null or visible not between 1000 and 120000 or fraction is null or not(fraction between .5 and 1)
        or elapsed_ms<visible then raise exception using errcode='22023',message='unqualified_impression'; end if;
      if d.qualified_at is null then
        select not exists(select 1 from recsys.daily_exposures where user_id=auth.uid() and post_id=p.id and day_utc=today)into first_view;
        insert into recsys.daily_exposures as e(user_id,post_id,day_utc,post_version,epoch)
          values(auth.uid(),p.id,today,p.version,s.epoch)
        on conflict(user_id,post_id,day_utc) do update set last_seen_at=statement_timestamp(),post_version=excluded.post_version,epoch=excluded.epoch,
          active_ms=case when e.post_version=excluded.post_version and e.epoch=excluded.epoch then e.active_ms else 0 end,
          opened=case when e.post_version=excluded.post_version and e.epoch=excluded.epoch then e.opened else false end,
          engaged_at=case when e.post_version=excluded.post_version and e.epoch=excluded.epoch then e.engaged_at else null end;
        if first_view then perform private.record_author_reach(p.author_id,auth.uid());end if;
        if first_view then insert into recsys.post_statistics as st(post_id,impressions)values(p.id,1)
          on conflict(post_id)do update set impressions=st.impressions+1; end if;
        update recsys.deliveries set qualified_at=statement_timestamp()where id=d.id;
      end if;
    else
      if d.qualified_at is null then raise exception using errcode='22023',message='impression_required'; end if;
      today:=(d.qualified_at at time zone 'UTC')::date;
      if kind='dwell' then
        active:=(event->>'active_ms')::integer;
        if active is null or active not between 0 and 120000 or active>elapsed_ms then
          raise exception using errcode='22023',message='invalid_active_time'; end if;
        update recsys.deliveries set active_ms=greatest(active_ms,active)where id=d.id;
        update recsys.daily_exposures set engaged_at=case when active>active_ms then statement_timestamp()else engaged_at end,
          active_ms=greatest(active_ms,active),last_seen_at=statement_timestamp()
          where user_id=auth.uid() and post_id=p.id and day_utc=today and epoch=s.epoch and post_version=p.version;
      else
        update recsys.deliveries set opened=true where id=d.id;
        update recsys.daily_exposures set engaged_at=case when not opened then statement_timestamp()else engaged_at end,
          opened=true,last_seen_at=statement_timestamp()
          where user_id=auth.uid() and post_id=p.id and day_utc=today and epoch=s.epoch and post_version=p.version;
      end if;
    end if;
    insert into recsys.telemetry_events(user_id,id,delivery_id,payload)values(auth.uid(),event_id,d.id,event);
    accepted:=accepted+1;
  end loop;
  if accepted>0 then
    update recsys.user_states set revision=revision+1 where user_id=auth.uid() returning * into s;
    perform private.queue_recommendation_refresh(auth.uid(),s.revision);
  end if;
  return jsonb_build_object('accepted',accepted,'duplicates',duplicates,'stale',stale,'revision',s.revision);
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
  ), ids as materialized(select id,array_agg(distinct source order by source) sources from pool group by id),
  authors as materialized(
    select distinct p.author_id,p.audience from ids join feed.posts p on p.id=ids.id
  ), allowed as materialized(select a.* from authors a where private.feed_post_visible(viewer,a.author_id,a.audience)),
  candidates as (
    select p.id,p.author_id,p.version,p.created_at,coalesce(em.embedding::text,'') vector,ids.sources,
      (exists(select 1 from social where author_id=p.author_id)or exists(select 1 from affinity where author_id=p.author_id)or exists(select 1 from followed where author_id=p.author_id)or 'friends_repost'=any(ids.sources)) social,coalesce(st.impressions,0)impressions,
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

create or replace function private.create_recommendation_fallback(s recsys.user_states)
returns uuid language plpgsql security definer set search_path='' as $$
declare snapshot uuid:=extensions.gen_random_uuid();
begin
  insert into recsys.feed_snapshots(id,user_id,epoch,revision,model,embedding_model,feature_version,policy_version)
    values(snapshot,s.user_id,s.epoch,s.revision,'fallback-v1',
      'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query','none','fallback-v1');
  insert into recsys.feed_snapshot_items(snapshot_id,position,post_id,post_version,reasons,sources)
    select snapshot,(row_number()over(order by p.created_at desc,p.id)-1)::integer,p.id,p.version,array['recent'],array['fresh']
    from (select * from feed.posts where created_at>statement_timestamp()-interval '7 days' and author_id<>s.user_id
      and deleted_at is null and moderation_status='allowed' order by created_at desc,id limit 500)p
    where private.recommendation_post_allowed(s.user_id,p::feed.posts)
    order by p.created_at desc,p.id limit 200;
  update recsys.user_states set current_snapshot=snapshot where user_id=s.user_id;
  return snapshot;
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
      and private.recommendation_post_allowed(auth.uid(),p)
    order by i.position limit requested_limit+1 loop
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

create function recsys.preparation_queue_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
    select jsonb_build_object(
        'refresh',jsonb_build_object('ready',(select count(*)from recsys.refresh_jobs where attempts<8 and available_at<=statement_timestamp()and(locked_until is null or locked_until<=statement_timestamp())),
          'failed',(select count(*)from recsys.refresh_jobs where attempts>=8),
          'oldest_wait_seconds',(select coalesce(max(extract(epoch from statement_timestamp()-requested_at)),0)from recsys.refresh_jobs where attempts<8)),
        'index',jsonb_build_object('live',(select count(*)from recsys.index_jobs where done_at is null and job_kind='live'and attempts<8),
          'backfill',(select count(*)from recsys.index_jobs where done_at is null and job_kind='backfill'and attempts<8),
          'failed',(select count(*)from recsys.index_jobs where done_at is null and attempts>=8)),
        'recent_publication',(
          select jsonb_build_object('samples',count(*),'p95_seconds',percentile_cont(.95)within group(order by extract(epoch from created_at-queued_at)))
          from(select created_at,queued_at from recsys.feed_snapshots where queued_at is not null order by created_at desc limit 1000)s));
$$;
revoke all on function recsys.claim_refresh_job(uuid,integer),recsys.claim_index_batch(uuid,text,text,integer),
    recsys.complete_index_batch(jsonb),recsys.enqueue_index_backfill(uuid,integer),recsys.preparation_queue_snapshot()
    from public,anon,authenticated,yap_feed_media_worker;
grant execute on function recsys.claim_refresh_job(uuid,integer),recsys.claim_index_batch(uuid,text,text,integer),
    recsys.complete_index_batch(jsonb),recsys.enqueue_index_backfill(uuid,integer),recsys.preparation_queue_snapshot()
    to yap_recommendation_worker;
revoke all on function private.create_author_statistics(),private.record_author_reach(uuid,uuid),private.stamp_feed_delivery_versions()
    from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
notify pgrst,'reload schema';

create or replace function private.queue_feed_post_index()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.text is not distinct from old.text
    and new.moderation_status is not distinct from old.moderation_status
    and new.deleted_at is not distinct from old.deleted_at then return null; end if;
  -- Invalidating the derived vector and recording the next job is part of the
  -- publication transaction, so neither can be lost on a worker/network outage.
  delete from recsys.post_embeddings where post_id = new.id;
  if new.deleted_at is null and new.moderation_status = 'allowed' and new.text<>'' then
    insert into recsys.index_jobs (post_id, post_version, model)
    values (new.id, new.version, 'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')
    on conflict (post_id, post_version, model) do update set
      job_kind = 'live', done_at = null, attempts = 0, available_at = statement_timestamp(), lease = null, locked_until = null, last_error = null;
  end if;
  return null;
end $$;

create or replace function recsys.complete_index_job(requested_id bigint, requested_lease uuid, requested_embedding extensions.vector)
returns boolean language plpgsql security definer set search_path = '' as $$
declare j recsys.index_jobs%rowtype; p feed.posts%rowtype;
begin
  select * into j from recsys.index_jobs where id = requested_id;
  if not found then return false; end if;
  -- Lock the source row before checking its version. An edit and publication of
  -- a derived vector must serialize, even if the edit commits during inference.
  select * into p from feed.posts where id = j.post_id for share;
  -- Always acquire source -> job locks, like the publication trigger, to avoid
  -- a deadlock between an edit and completion of inference for the same post.
  select * into j from recsys.index_jobs where id = requested_id and lease = requested_lease
    and done_at is null and locked_until > clock_timestamp() for update;
  if not found then return false; end if;
  if j.model=(recsys.pipeline_contract()->>'embedding_model')and p.id is not null and p.version = j.post_version and p.deleted_at is null and p.moderation_status = 'allowed'
    and not private.is_account_globally_banned(p.author_id)
    and not private.is_account_pending_deletion(p.author_id) then
    if requested_embedding is null then
      raise exception using errcode = '22023', message = 'embedding_required';
    end if;
    insert into recsys.post_embeddings (post_id, post_version, model, embedding)
      values (p.id, p.version, j.model, requested_embedding)
    on conflict (post_id) do update set post_version = excluded.post_version,
      model = excluded.model, embedding = excluded.embedding, updated_at = statement_timestamp();
  end if;
  update recsys.index_jobs set done_at = statement_timestamp(), lease = null, locked_until = null, last_error = null
    where id = j.id;
  return true;
end $$;
