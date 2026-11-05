-- Bounded admission is shared by every client/worker. The hot path updates one
-- small counter row; it never counts the complete post or Storage history.
-- Storage supplies this metadata from the received body. The declared byte
-- budget is meaningful only if a mismatched body cannot become a stored object.
create function private.feed_upload_metadata_matches(object_path text,object_metadata jsonb)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
    where u.source_path=object_path and d.owner_id=auth.uid()
      -- Preflight contentLength can include multipart framing. Only the
      -- backend-measured size describes the file itself.
      and(not(object_metadata?'size')or object_metadata->'size'=to_jsonb(u.declared_bytes))
      and object_metadata->>'mimetype'=u.declared_mime);
$$;
revoke all on function private.feed_upload_metadata_matches(text,jsonb)from public,anon,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.feed_upload_metadata_matches(text,jsonb)to authenticated;
alter policy "Feed upload reservations"on storage.objects
  with check(bucket_id='feed-uploads'and storage.allow_only_operation('object.upload')
    and private.feed_upload_allowed(name)and private.feed_upload_metadata_matches(name,metadata));

-- Some Storage versions finalize with an internal role after an RLS preflight.
-- Validate actual backend metadata independently of that role/preflight. Older
-- preflight records contain contentLength but no measured size and roll back.
create function private.validate_feed_upload_metadata()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.bucket_id='feed-uploads'and new.metadata?'size'and not exists(
    select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
    where u.source_path=new.name and d.owner_id::text=new.owner_id and u.state='waiting'
      and d.cancelled_at is null and d.published_at is null and d.expires_at>statement_timestamp()
      and not private.is_account_globally_banned(d.owner_id)and not private.is_account_pending_deletion(d.owner_id)
      and new.metadata->'size'=to_jsonb(u.declared_bytes)and new.metadata->>'mimetype'=u.declared_mime)then
    raise exception using errcode='22023',message='feed_photo_metadata_mismatch';
  end if;
  return new;
end $$;
revoke all on function private.validate_feed_upload_metadata()from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
create trigger feed_upload_metadata_guard before insert or update of metadata on storage.objects
  for each row execute function private.validate_feed_upload_metadata();

create table media.capacity (
  singleton boolean primary key default true check(singleton),
  active integer not null default 0 check(active>=0),
  unfinished integer not null default 0 check(unfinished>=0),
  reserved_bytes bigint not null default 0 check(reserved_bytes>=0),
  temporary_bytes bigint not null default 0 check(temporary_bytes>=0),
  max_active integer not null default 256 check(max_active between 1 and 10000),
  max_unfinished integer not null default 120 check(max_unfinished between 1 and 10000),
  max_reserved_bytes bigint not null default 536870912 check(max_reserved_bytes between 5242880 and 107374182400),
  max_temporary_bytes bigint not null default 1073741824 check(max_temporary_bytes between 16777216 and 107374182400),
  max_queue_age_seconds integer not null default 60 check(max_queue_age_seconds between 1 and 1800),
  max_cleanup_backlog integer not null default 2048 check(max_cleanup_backlog between 1 and 100000),
  max_parallel integer not null default 2 check(max_parallel between 1 and 8),
  max_workers integer not null default 2 check(max_workers between 1 and 16),
  max_worker_connections integer not null default 6 check(max_worker_connections between 2 and 32),
  retry_after_seconds integer not null default 15 check(retry_after_seconds between 1 and 300),
  paused boolean not null default false
);
insert into media.capacity(singleton)values(true);
create table media.reservations (
  photo_id uuid primary key references feed.photo_uploads(id)on delete cascade,
  draft_id uuid not null references feed.post_drafts(id)on delete cascade,
  bytes integer not null check(bytes between 1 and 5242880),
  unfinished boolean not null,
  expires_at timestamptz not null
);
create index media_reservations_expiry_idx on media.reservations(expires_at,photo_id);
create index media_reservations_draft_idx on media.reservations(draft_id,photo_id);
create index media_cleanup_diagnostics_idx on media.cleanup_jobs(available_at,bucket,path);
create table media.processing_slots (
  id integer primary key check(id between 1 and 8),
  photo_id uuid references feed.photo_uploads(id)on delete set null,
  lease uuid,
  expires_at timestamptz
);
insert into media.processing_slots(id)select generate_series(1,8);
create index media_processing_slots_photo_idx on media.processing_slots(photo_id);
create table media.workers (
  id uuid primary key,
  concurrency integer not null check(concurrency between 1 and 2),
  connections integer not null check(connections between 2 and 3),
  expires_at timestamptz not null
);
create table media.processing_metrics (
  singleton boolean primary key default true check(singleton),
  since timestamptz not null default statement_timestamp(),
  claimed bigint not null default 0,
  retries bigint not null default 0,
  completed bigint not null default 0,
  rejected bigint not null default 0,
  failed_attempts bigint not null default 0,
  wait_count bigint not null default 0,
  wait_ms double precision not null default 0,
  duration_count bigint not null default 0,
  duration_ms double precision not null default 0,
  wait_buckets bigint[]not null default '{0,0,0,0,0,0,0,0}',
  duration_buckets bigint[]not null default '{0,0,0,0,0,0,0,0}',
  cleanup_completed bigint not null default 0,
  cleanup_failed bigint not null default 0
);
insert into media.processing_metrics(singleton)values(true);
alter table feed.photo_uploads add column queued_at timestamptz,add column last_started_at timestamptz,
  add column attempt_finished_at timestamptz,add column worker_id uuid;
alter table media.cleanup_jobs add column estimated_bytes bigint not null default 5242880 check(estimated_bytes between 1 and 5242880);
update media.cleanup_jobs j set estimated_bytes=case when bucket='feed-uploads'then coalesce((select declared_bytes from feed.photo_uploads where source_path=j.path),5242880)
  when right(path,14)='/thumbnail.jpg'then 1048576 else 5242880 end;
update feed.photo_uploads set queued_at=created_at where state<>'waiting';
insert into media.reservations(photo_id,draft_id,bytes,unfinished,expires_at)
select p.id,p.draft_id,p.declared_bytes,p.state<>'ready',d.expires_at from feed.photo_uploads p join feed.post_drafts d on d.id=p.draft_id
where d.cancelled_at is null and d.published_at is null and d.expires_at>statement_timestamp()and p.state in('waiting','queued','processing','ready');
update media.capacity set active=(select count(*)from media.reservations),
  unfinished=(select count(*)from media.reservations where unfinished),reserved_bytes=coalesce((select sum(bytes)from media.reservations),0),
  temporary_bytes=coalesce((select sum(estimated_bytes)from media.cleanup_jobs),0);

do $$declare name text;begin
  foreach name in array array['capacity','reservations','processing_slots','workers','processing_metrics']loop
    execute 'alter table media.'||name||' enable row level security';
    execute 'revoke all on media.'||name||' from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker';
  end loop;
end $$;

create function private.media_busy(retry_seconds integer)
returns void language plpgsql set search_path='' as $$
begin
  raise sqlstate 'PGRST' using message=jsonb_build_object('code','media_capacity_exceeded','message','media_temporarily_busy',
    'details',jsonb_build_object('retry_after_seconds',retry_seconds)::text,'hint','Retry the same reservation after the indicated delay')::text,
    -- PostgREST adds its recovery Retry-After header to every 503, including
    -- application errors. 429 preserves our admission delay unambiguously.
    detail=jsonb_build_object('status',429,'headers',jsonb_build_object('Retry-After',retry_seconds::text))::text;
end $$;

create function private.release_media_reservation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update media.capacity set active=active-1,unfinished=unfinished-case when old.unfinished then 1 else 0 end,
    reserved_bytes=reserved_bytes-old.bytes where singleton;
  return null;
end $$;
create constraint trigger media_reservation_release after delete on media.reservations deferrable initially deferred
  for each row execute function private.release_media_reservation();
create function private.adjust_media_reservation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.unfinished<>new.unfinished then
    update media.capacity set unfinished=unfinished+case when new.unfinished then 1 else -1 end where singleton;
  end if;
  return null;
end $$;
create constraint trigger media_reservation_adjust after update on media.reservations deferrable initially deferred
  for each row execute function private.adjust_media_reservation();

create function private.account_media_cleanup()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT'then
    new.estimated_bytes:=case when new.bucket='feed-uploads'then coalesce((select declared_bytes from feed.photo_uploads where source_path=new.path),5242880)
      when right(new.path,14)='/thumbnail.jpg'then 1048576 else 5242880 end;
    return new;
  end if;
  update media.capacity set temporary_bytes=temporary_bytes-old.estimated_bytes where singleton;
  if old.lease is not null then
    update media.processing_metrics set cleanup_completed=cleanup_completed+1 where singleton;
  end if;
  return null;
end $$;
create function private.charge_media_cleanup()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Deletion of existing posts is never blocked by an admission limit. It may
  -- temporarily increase the cleanup debt; only new uploads/attempts are gated.
  update media.capacity set temporary_bytes=temporary_bytes+new.estimated_bytes where singleton;
  return null;
end $$;
create trigger media_cleanup_estimate before insert on media.cleanup_jobs for each row execute function private.account_media_cleanup();
create constraint trigger media_cleanup_release after delete on media.cleanup_jobs deferrable initially deferred
  for each row execute function private.account_media_cleanup();
create constraint trigger media_cleanup_charge after insert on media.cleanup_jobs deferrable initially deferred
  for each row execute function private.charge_media_cleanup();
create function private.observe_cleanup_attempt()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.lease is not null and new.lease is null then
    perform 1 from media.capacity where singleton for update;
    update media.processing_metrics set cleanup_failed=cleanup_failed+1 where singleton;
  end if;
  return null;
end $$;
create constraint trigger media_cleanup_failure after update on media.cleanup_jobs deferrable initially deferred
  for each row execute function private.observe_cleanup_attempt();

create function media.expire_reservations(requested_limit integer default 64)
returns integer language plpgsql security definer set search_path='' as $$
declare affected integer;
begin
  if requested_limit not between 1 and 256 then raise exception using errcode='22023',message='invalid_batch';end if;
  delete from media.reservations where photo_id in(select photo_id from media.reservations where expires_at<=statement_timestamp()
    order by expires_at,photo_id for update skip locked limit requested_limit);
  get diagnostics affected=row_count;
  return affected;
end $$;

create function private.account_media_photo()
returns trigger language plpgsql security definer set search_path='' as $$
declare d feed.post_drafts%rowtype; c media.capacity%rowtype; reservation media.reservations%rowtype;
  oldest timestamptz; cleanup_count integer; unfinished_now boolean;
begin
  if tg_op='INSERT'then
    select * into d from feed.post_drafts where id=new.draft_id;
    if d.published_at is not null or d.cancelled_at is not null or d.expires_at<=statement_timestamp()then return null;end if;
    if new.state not in('waiting','queued','processing','ready')then return null;end if;
    -- Reserve is a single-photo RPC. Lock a previously registered source path
    -- before its counter, including rare retries after old draft GC.
    perform 1 from media.cleanup_jobs where bucket='feed-uploads'and path=new.source_path for update;
    select * into c from media.capacity where singleton;
    -- Only admitted, unfinished work participates in the age check. This set is
    -- bounded by capacity, independent of the size of the published history.
    select min(p.queued_at)into oldest from media.reservations r join feed.photo_uploads p on p.id=r.photo_id
      where r.unfinished and r.expires_at>statement_timestamp()and p.state in('queued','processing')
        and(p.attempts<8 or(p.state='processing'and p.locked_until>statement_timestamp()));
    select count(*)into cleanup_count from(select 1 from media.cleanup_jobs where available_at<=statement_timestamp()
      limit c.max_cleanup_backlog+1)q;
    if c.paused or oldest<statement_timestamp()-make_interval(secs=>c.max_queue_age_seconds)
      or cleanup_count>c.max_cleanup_backlog then perform private.media_busy(c.retry_after_seconds);end if;
    unfinished_now:=new.state<>'ready';
    update media.capacity set active=active+1,unfinished=unfinished+case when unfinished_now then 1 else 0 end,reserved_bytes=reserved_bytes+new.declared_bytes
      where singleton and not paused and active<max_active and unfinished+case when unfinished_now then 1 else 0 end<=max_unfinished
        and reserved_bytes+new.declared_bytes<=max_reserved_bytes
        and temporary_bytes+new.declared_bytes+6291456<=max_temporary_bytes returning * into c;
    if not found then
      perform private.media_busy((select retry_after_seconds from media.capacity where singleton));
    end if;
    insert into media.reservations(photo_id,draft_id,bytes,unfinished,expires_at)values(new.id,new.draft_id,new.declared_bytes,unfinished_now,d.expires_at);
  else
    if new.state not in('waiting','queued','processing','ready')then
      delete from media.reservations where photo_id=new.id;
    else
      select * into reservation from media.reservations where photo_id=new.id for update;
      if found then
        unfinished_now:=new.state<>'ready';
        if reservation.unfinished<>unfinished_now then
          update media.reservations set unfinished=unfinished_now where photo_id=new.id;
        end if;
      end if;
    end if;
  end if;
  return null;
end $$;
create trigger feed_photo_capacity after insert or update of state on feed.photo_uploads for each row execute function private.account_media_photo();

create function private.release_media_draft()
returns trigger language plpgsql security definer set search_path='' as $$
declare p record;
begin
  if new.cancelled_at is not null or new.published_at is not null then
    delete from media.reservations where draft_id=new.id;
    for p in select * from feed.photo_uploads where draft_id=new.id and state<>'attached'loop
      perform private.queue_feed_media_delete('feed-uploads',p.source_path,statement_timestamp()+interval '15 minutes');
      perform private.queue_feed_media_delete('feed-media',p.image_path,statement_timestamp()+interval '15 minutes');
      perform private.queue_feed_media_delete('feed-media',p.thumbnail_path,statement_timestamp()+interval '15 minutes');
    end loop;
  end if;
  return null;
end $$;
create trigger feed_draft_capacity_release after update of cancelled_at,published_at on feed.post_drafts
  for each row execute function private.release_media_draft();

create function private.time_media_photo()
returns trigger language plpgsql set search_path='' as $$
begin
  if old.state='waiting'and new.state='queued'then new.queued_at:=clock_timestamp();end if;
  if new.state='processing'and new.lease is distinct from old.lease then new.last_started_at:=clock_timestamp();end if;
  if old.state='processing'and new.state in('ready','queued','rejected')then new.attempt_finished_at:=clock_timestamp();end if;
  return new;
end $$;
create trigger feed_photo_attempt_clock before update of state,lease on feed.photo_uploads for each row execute function private.time_media_photo();
create function private.observe_media_photo()
returns trigger language plpgsql security definer set search_path='' as $$
declare waited double precision; elapsed double precision; bucket integer;
begin
  -- Deferred until source changes finish. Use counter -> metrics ordering.
  perform 1 from media.capacity where singleton for update;
  if new.state='processing'and new.lease is distinct from old.lease then
    waited:=greatest(0,extract(epoch from(new.last_started_at-coalesce(old.attempt_finished_at,new.queued_at,new.created_at)))*1000);
    bucket:=width_bucket(waited,array[100::float8,500,1000,5000,10000,30000,60000])+1;
    update media.processing_metrics set claimed=claimed+1,retries=retries+case when new.attempts>1 then 1 else 0 end,
      wait_count=wait_count+1,wait_ms=wait_ms+waited,wait_buckets[bucket]=wait_buckets[bucket]+1 where singleton;
  elsif old.state='processing'and new.state in('ready','queued','rejected')then
    elapsed:=greatest(0,extract(epoch from(new.attempt_finished_at-coalesce(old.last_started_at,new.attempt_finished_at)))*1000);
    bucket:=width_bucket(elapsed,array[100::float8,500,1000,5000,10000,30000,60000])+1;
    update media.processing_metrics set completed=completed+case when new.state='ready'then 1 else 0 end,
      rejected=rejected+case when new.state='rejected'then 1 else 0 end,failed_attempts=failed_attempts+case when new.state='queued'then 1 else 0 end,
      duration_count=duration_count+1,duration_ms=duration_ms+elapsed,duration_buckets[bucket]=duration_buckets[bucket]+1 where singleton;
  end if;
  return null;
end $$;
create constraint trigger feed_photo_observability after update on feed.photo_uploads deferrable initially deferred
  for each row execute function private.observe_media_photo();
create function private.release_media_processing_slot()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.state='processing'and new.state in('ready','queued','rejected')then
    update media.processing_slots set photo_id=null,lease=null,expires_at=null where photo_id=new.id and lease=old.lease;
  end if;
  return null;
end $$;
create trigger feed_photo_slot_release after update of state on feed.photo_uploads for each row execute function private.release_media_processing_slot();

create function media.register_worker(requested_id uuid,requested_concurrency integer,requested_connections integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare c media.capacity%rowtype; total integer; connections integer;
begin
  if requested_id is null or requested_concurrency not between 1 and 2 or requested_connections<>requested_concurrency+1 then
    raise exception using errcode='22023',message='invalid_worker_budget';end if;
  perform pg_advisory_xact_lock(hashtextextended('media-worker-registration',0));
  delete from media.workers where expires_at<=statement_timestamp();
  select * into c from media.capacity where singleton;
  select count(*),coalesce(sum(w.connections),0)into total,connections from media.workers w where id<>requested_id;
  if total>=c.max_workers or connections+requested_connections>c.max_worker_connections then return false;end if;
  insert into media.workers(id,concurrency,connections,expires_at)values(requested_id,requested_concurrency,requested_connections,statement_timestamp()+interval '30 seconds')
    on conflict(id)do update set expires_at=excluded.expires_at;
  return true;
end $$;
create function media.heartbeat_worker(requested_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform media.expire_reservations(64);
  update media.workers set expires_at=statement_timestamp()+interval '30 seconds'where id=requested_id and expires_at>statement_timestamp();
  return found;
end $$;
create function media.unregister_worker(requested_id uuid)
returns void language sql security definer set search_path='' as $$delete from media.workers where id=requested_id;$$;

create function media.queue_snapshot()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  with admitted as materialized(select p.*,r.expires_at from media.reservations r join feed.photo_uploads p on p.id=r.photo_id),
  pending_cleanup as materialized(select * from media.cleanup_jobs order by available_at,bucket,path limit 10001)
  select jsonb_build_object('at',statement_timestamp(),'capacity',to_jsonb(c)-'singleton',
    'photos',jsonb_build_object('waiting',(select count(*)from admitted where state='waiting'),
      'queued',(select count(*)from admitted where state='queued'and attempts<8),
      'processing',(select count(*)from admitted where state='processing'and locked_until>statement_timestamp()),
      'retrying',(select count(*)from admitted where attempts>0 and state='queued'and attempts<8),
      'failed',(select count(*)from admitted where attempts>=8 and(locked_until is null or locked_until<=statement_timestamp())),
      'ready',(select count(*)from admitted where state='ready'),
      'expired_reservations',(select count(*)from admitted where expires_at<=statement_timestamp()),
      'oldest_queue_age_seconds',coalesce((select greatest(0,extract(epoch from statement_timestamp()-min(queued_at)))from admitted
        where state in('queued','processing')and(attempts<8 or locked_until>statement_timestamp())and expires_at>statement_timestamp()),0)),
    'cleanup',jsonb_build_object('count_capped',(select count(*)from pending_cleanup),'count_is_capped',(select count(*)from pending_cleanup)>10000,
      'due',(select count(*)from pending_cleanup where available_at<=statement_timestamp()),
      'failed',(select count(*)from pending_cleanup where attempts>=8),
      'oldest_due_age_seconds',coalesce((select greatest(0,extract(epoch from statement_timestamp()-min(available_at)))from pending_cleanup where available_at<=statement_timestamp()),0)),
    'workers',jsonb_build_object('active',(select count(*)from media.workers where expires_at>statement_timestamp()),
      'connections_reserved',coalesce((select sum(connections)from media.workers where expires_at>statement_timestamp()),0),
      'processing_slots',(select count(*)from media.processing_slots s join feed.photo_uploads p on p.id=s.photo_id
        where s.expires_at>statement_timestamp()and p.state='processing'and p.lease=s.lease)),
    'metrics',to_jsonb(m)-'singleton','histogram_upper_bounds_ms',array[100,500,1000,5000,10000,30000,60000])into result
  from media.capacity c cross join media.processing_metrics m;
  return result;
end $$;

create or replace function media.contract()
returns jsonb language sql immutable set search_path='' as $$
  select '{"version":1,"processor":"jpeg-v1","max_bytes":5242880,"capacity_version":1}'::jsonb;
$$;

revoke all on function private.media_busy(integer),private.release_media_reservation(),private.account_media_cleanup(),private.charge_media_cleanup(),private.account_media_photo(),
  private.release_media_draft(),private.time_media_photo(),private.observe_media_photo(),private.adjust_media_reservation(),
  private.observe_cleanup_attempt(),private.release_media_processing_slot()from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function media.expire_reservations(integer),media.register_worker(uuid,integer,integer),media.heartbeat_worker(uuid),
  media.unregister_worker(uuid),media.queue_snapshot()from public,anon,authenticated,yap_recommendation_worker;
grant execute on function media.expire_reservations(integer),media.register_worker(uuid,integer,integer),media.heartbeat_worker(uuid),
  media.unregister_worker(uuid),media.queue_snapshot()to yap_feed_media_worker;

create or replace function media.claim_photo(requested_lease uuid,requested_worker uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype; d feed.post_drafts%rowtype; prefix text; slot integer; limits media.capacity%rowtype;
begin
  if requested_lease is null then raise exception using errcode='22023',message='lease_required';end if;
  if requested_worker is not null and not exists(select 1 from media.workers where id=requested_worker and expires_at>statement_timestamp())then
    return null;end if;
  select s.id into slot from media.processing_slots s where s.id<=(select max_parallel from media.capacity where singleton)
    and(s.expires_at is null or s.expires_at<=statement_timestamp()or not exists(select 1 from feed.photo_uploads live
      where live.id=s.photo_id and live.lease=s.lease and live.state='processing'and live.locked_until>statement_timestamp()))
    order by s.id for update skip locked limit 1;
  if not found then return null;end if;
  select u.* into p from feed.photo_uploads u join feed.post_drafts draft on draft.id=u.draft_id
    where u.state in('queued','processing')and u.attempts<8 and u.available_at<=statement_timestamp()
      and(u.locked_until is null or u.locked_until<=statement_timestamp())
      and draft.expires_at>statement_timestamp()and draft.cancelled_at is null and draft.published_at is null
      and not private.is_account_globally_banned(draft.owner_id)and not private.is_account_pending_deletion(draft.owner_id)
    order by u.available_at,u.id for update of u skip locked limit 1;
  if not found then return null;end if;
  select * into d from feed.post_drafts where id=p.draft_id;
  -- All paths that need both counters/metrics acquire capacity first.
  select * into limits from media.capacity where singleton for update;
  if limits.temporary_bytes+6291456>limits.max_temporary_bytes then return null;end if;
  prefix:=d.owner_id::text||'/'||p.draft_id::text||'/'||p.id::text||'/'||requested_lease::text;
  update feed.photo_uploads set state='processing',lease=requested_lease,locked_until=statement_timestamp()+interval '2 minutes',
    attempts=attempts+1,worker_id=requested_worker where id=p.id;
  update media.processing_slots set photo_id=p.id,lease=requested_lease,expires_at=statement_timestamp()+interval '2 minutes'where id=slot;
  -- Register every attempted output before sending bytes. Failed/stale attempts
  -- therefore remain discoverable even if the process crashes before completion.
  perform private.queue_feed_media_delete('feed-media',prefix||'/image.jpg',statement_timestamp()+interval '17 minutes');
  perform private.queue_feed_media_delete('feed-media',prefix||'/thumbnail.jpg',statement_timestamp()+interval '17 minutes');
  return jsonb_build_object('id',p.id,'lease',requested_lease,'source_path',p.source_path,'declared_bytes',p.declared_bytes,
    'declared_mime',p.declared_mime,'image_path',prefix||'/image.jpg','thumbnail_path',prefix||'/thumbnail.jpg');
end $$;
create or replace function media.claim_photo(requested_lease uuid)
returns jsonb language sql security definer set search_path='' as $$select media.claim_photo(requested_lease,null);$$;
revoke all on function media.claim_photo(uuid,uuid)from public,anon,authenticated,yap_recommendation_worker;
grant execute on function media.claim_photo(uuid,uuid)to yap_feed_media_worker;
create or replace function media.complete_photo(requested_id uuid,requested_lease uuid,result jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype; d feed.post_drafts%rowtype; prefix text;
begin
  select * into p from feed.photo_uploads where id=requested_id and state='processing'and lease=requested_lease
    and locked_until>clock_timestamp()for update;
  if not found then return false;end if;
  if p.worker_id is not null and not exists(select 1 from media.workers where id=p.worker_id and expires_at>statement_timestamp())then return false;end if;
  select * into d from feed.post_drafts where id=p.draft_id and cancelled_at is null and published_at is null and expires_at>statement_timestamp();
  if not found or private.is_account_globally_banned(d.owner_id)or private.is_account_pending_deletion(d.owner_id)then return false;end if;
  prefix:=d.owner_id::text||'/'||p.draft_id::text||'/'||p.id::text||'/'||requested_lease::text;
  if result is null or not exists(select 1 from storage.objects where bucket_id='feed-media'and name=prefix||'/image.jpg'
    and metadata->>'mimetype'='image/jpeg'and(metadata->>'size')::bigint=(result->>'image_bytes')::integer)
    or not exists(select 1 from storage.objects where bucket_id='feed-media'and name=prefix||'/thumbnail.jpg'
      and metadata->>'mimetype'='image/jpeg'and(metadata->>'size')::bigint=(result->>'thumbnail_bytes')::integer)then
    raise exception using errcode='22023',message='prepared_photo_missing';end if;
  update feed.photo_uploads set state='ready',lease=null,locked_until=null,failure_code=null,
    image_path=prefix||'/image.jpg',thumbnail_path=prefix||'/thumbnail.jpg',width=(result->>'width')::integer,
    height=(result->>'height')::integer,image_bytes=(result->>'image_bytes')::integer,
    thumbnail_bytes=(result->>'thumbnail_bytes')::integer,sha256=result->>'sha256'where id=p.id;
  perform private.queue_feed_media_delete('feed-uploads',p.source_path);
  return true;
end $$;
create or replace function media.complete_cleanup(requested_bucket text,requested_path text,requested_lease uuid,succeeded boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare affected integer;
begin
  if succeeded and not exists(select 1 from storage.objects where bucket_id=requested_bucket and name=requested_path)then
    delete from media.cleanup_jobs where bucket=requested_bucket and path=requested_path and lease=requested_lease
    and locked_until>statement_timestamp();
    get diagnostics affected=row_count;
    return affected>0;
  else update media.cleanup_jobs set lease=null,locked_until=null,
    available_at=statement_timestamp()+make_interval(secs=>least(3600,power(2,attempts)::integer))
    where bucket=requested_bucket and path=requested_path and lease=requested_lease and locked_until>statement_timestamp();end if;
  return false;
end $$;
create or replace function media.claim_cleanup(requested_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j media.cleanup_jobs%rowtype;
begin
  if requested_lease is null then raise exception using errcode='22023',message='lease_required';end if;
  -- Bounded skipping prevents retained files from starving actual deletions.
  for iteration in 1..20 loop
    select * into j from media.cleanup_jobs where attempts<8 and available_at<=statement_timestamp()
      and(locked_until is null or locked_until<=statement_timestamp())order by available_at,bucket,path for update skip locked limit 1;
    if not found then return null;end if;
    if private.feed_media_is_retained(j.bucket,j.path)then
      update media.cleanup_jobs set available_at=statement_timestamp()+interval '1 hour'where bucket=j.bucket and path=j.path;
      continue;
    end if;
    -- Ready unpublished images remain available for publication until the draft expires.
    if j.bucket='feed-media'and exists(select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
      where j.path in(u.image_path,u.thumbnail_path)and u.state='ready'and d.expires_at>statement_timestamp()and d.cancelled_at is null and d.published_at is null)then
      update media.cleanup_jobs set available_at=statement_timestamp()+interval '1 hour'where bucket=j.bucket and path=j.path;
      continue;
    end if;
    update media.cleanup_jobs set lease=requested_lease,locked_until=statement_timestamp()+interval '1 minute',attempts=attempts+1
      where bucket=j.bucket and path=j.path;
    return jsonb_build_object('bucket',j.bucket,'path',j.path,'lease',requested_lease);
  end loop;
  return null;
end $$;
create or replace function private.feed_media_is_retained(bucket_name text,object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
    left join feed.posts post on post.id=d.id
    where(bucket_name='feed-uploads'and u.source_path=object_path and u.state in('waiting','queued','processing')
      and d.cancelled_at is null and d.published_at is null and d.expires_at>statement_timestamp())
    or(bucket_name='feed-media'and object_path in(u.image_path,u.thumbnail_path)
      and u.state='attached'and post.deleted_at is null and post.id is not null));
$$;

create or replace function private.feed_photo_status(photo feed.photo_uploads)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',photo.id,'slot',photo.slot,'state',case
    when photo.state='attached'then 'attached'
    when d.cancelled_at is not null then 'cancelled'
    when d.published_at is not null then 'discarded'
    when d.expires_at<=statement_timestamp()then 'expired'
    when photo.state in('queued','processing')and photo.attempts>=8 and(photo.locked_until is null or photo.locked_until<statement_timestamp())then 'failed'
    else photo.state end,'failure_code',photo.failure_code)
  from feed.post_drafts d where d.id=photo.draft_id;
$$;

create or replace function private.get_feed_photo_status_impl(requested_post uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d feed.post_drafts%rowtype; photos jsonb;
begin
  perform private.consume_feed_media_quota('status');
  select * into d from feed.post_drafts where id=requested_post and owner_id=auth.uid();
  if not found then raise exception using errcode='PT404',message='draft_not_found';end if;
  select coalesce(jsonb_agg(private.feed_photo_status(p)order by p.slot),'[]'::jsonb)into photos from feed.photo_uploads p where p.draft_id=d.id;
  return jsonb_build_object('post_id',d.id,'photos',photos,'state',case when d.cancelled_at is not null then 'cancelled'when d.published_at is not null then 'published'when d.expires_at<=statement_timestamp()then 'expired'else 'active'end,'expires_at',d.expires_at,'cancelled',d.cancelled_at is not null,'published',d.published_at is not null);
end $$;
create or replace function media.maintenance(retry_failed boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
  perform media.expire_reservations(256);
  delete from media.workers where expires_at<=statement_timestamp()-interval '1 day';
  delete from feed.post_drafts where id in(select id from feed.post_drafts where published_at is null
    and expires_at<statement_timestamp()-interval '1 day'order by expires_at for update skip locked limit 100);
  get diagnostics removed=row_count;
  if retry_failed then
    update feed.photo_uploads set attempts=0,available_at=statement_timestamp(),failure_code=null where id in(
      select id from feed.photo_uploads where state in('queued','processing')and attempts=8
        and(locked_until is null or locked_until<statement_timestamp())for update skip locked limit 100);
    update media.cleanup_jobs set attempts=0,available_at=statement_timestamp()where(bucket,path)in(
      select bucket,path from media.cleanup_jobs where attempts=8 and(locked_until is null or locked_until<statement_timestamp())
        for update skip locked limit 100);
  end if;
  return removed;
end $$;
create or replace function private.reserve_feed_photo_impl(requested_post uuid,requested_photo uuid,requested_bytes integer,requested_mime text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d feed.post_drafts%rowtype; p feed.photo_uploads%rowtype; next_slot integer; reserved integer;
begin
  perform private.consume_feed_media_quota('reserve');
  if requested_post is null or requested_photo is null or requested_bytes is null or requested_bytes not between 1 and 5242880
    or requested_mime is null or requested_mime not in('image/jpeg','image/png')then
    raise exception using errcode='22023',message='invalid_photo_reservation';end if;
  -- The quota row serializes this user's reservations, including new drafts.
  perform pg_advisory_xact_lock(hashtextextended('feed-create:'||requested_post::text,0));
  select * into d from feed.post_drafts where id=requested_post for update;
  if found then
    if d.owner_id=auth.uid()and d.published_at is null and d.cancelled_at is null and d.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='photo_reservation_expired';end if;
    if d.owner_id<>auth.uid()or d.published_at is not null or d.cancelled_at is not null or d.expires_at<=statement_timestamp()then
      raise exception using errcode='22023',message='draft_unavailable';end if;
  else
    if exists(select 1 from feed.posts where id=requested_post)then raise exception using errcode='23505',message='post_id_conflict';end if;
    if(select count(*)from feed.post_drafts where owner_id=auth.uid()and published_at is null and cancelled_at is null
      and expires_at>statement_timestamp())>=4 then raise exception using errcode='42901',message='too_many_drafts';end if;
    insert into feed.post_drafts(id,owner_id)values(requested_post,auth.uid())returning * into d;
  end if;
  select * into p from feed.photo_uploads where id=requested_photo;
  if found then
    if p.draft_id<>d.id or p.declared_bytes<>requested_bytes or p.declared_mime<>requested_mime then
      raise exception using errcode='23505',message='photo_id_conflict';end if;
  else
    select count(*)into reserved from feed.photo_uploads u join feed.post_drafts draft on draft.id=u.draft_id
      where draft.owner_id=auth.uid()and u.created_at>statement_timestamp()-interval '1 hour';
    if reserved>=48 then raise exception using errcode='42901',message='photo_hourly_rate_limited';end if;
    select count(*)into next_slot from feed.photo_uploads where draft_id=d.id;
    if next_slot>=3 then raise exception using errcode='22023',message='too_many_photos';end if;
    insert into feed.photo_uploads(id,draft_id,slot,declared_bytes,declared_mime,source_path)
      values(requested_photo,d.id,next_slot,requested_bytes,requested_mime,
        auth.uid()::text||'/'||d.id::text||'/'||requested_photo::text||'/source')returning * into p;
    perform private.queue_feed_media_delete('feed-uploads',p.source_path,d.expires_at+interval '15 minutes');
  end if;
  return private.feed_photo_status(p)||jsonb_build_object('post_id',d.id,'bucket','feed-uploads','path',p.source_path,'expires_at',d.expires_at,
    'max_bytes',5242880,'upload_upsert',false);
end $$;
create or replace function private.confirm_feed_photo_impl(requested_photo uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype;
begin
  perform private.consume_feed_media_quota('confirm');
  if exists(select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id where u.id=requested_photo and d.owner_id=auth.uid()and d.expires_at<=statement_timestamp()and d.published_at is null and d.cancelled_at is null)then raise exception using errcode='PT410',message='photo_reservation_expired';end if;
  select u.* into p from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
    where u.id=requested_photo and d.owner_id=auth.uid()and d.published_at is null and d.cancelled_at is null
      and d.expires_at>statement_timestamp()for update of u;
  if not found then raise exception using errcode='22023',message='photo_unavailable';end if;
  if p.state='waiting'then
    if not exists(select 1 from storage.objects o where o.bucket_id='feed-uploads'and o.name=p.source_path
      and o.owner_id=auth.uid()::text and(o.metadata->>'size')::bigint=p.declared_bytes and o.metadata->>'mimetype'=p.declared_mime)then
      raise exception using errcode='22023',message='photo_upload_missing_or_mismatched';end if;
    update feed.photo_uploads set state='queued',available_at=statement_timestamp()where id=p.id returning * into p;
  end if;
  return private.feed_photo_status(p);
end $$;
create or replace function private.publish_feed_post_impl(requested_id uuid,requested_text text,requested_audience text,requested_language text,
  requested_photos uuid[],requested_location jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.posts%rowtype; d feed.post_drafts%rowtype; total integer; attached integer; lat float8; lon float8; fingerprint jsonb;
begin
  perform private.require_active_account();
  total:=coalesce(cardinality(requested_photos),0);
  if requested_id is null or requested_text is null or char_length(requested_text)>1000
    or(requested_text<>''and requested_text!~'[^[:space:]]')or(requested_text=''and total=0)
    or requested_audience is null or requested_audience not in('public','friends')
    or requested_language is null or requested_language not in('ru','en')or total>3 or requested_photos is null
    or(select count(distinct id)from unnest(requested_photos)id)<>total then
    raise exception using errcode='22023',message='invalid_post';end if;
  if requested_location is not null then
    if jsonb_typeof(requested_location)<>'object'or not(requested_location?'latitude'and requested_location?'longitude')
      or exists(select 1 from jsonb_object_keys(requested_location)k where k not in('latitude','longitude'))then
      raise exception using errcode='22023',message='invalid_post_location';end if;
    lat:=(requested_location->>'latitude')::float8;lon:=(requested_location->>'longitude')::float8;
    if lat is null or lon is null or not(lat between -90 and 90 and lon between -180 and 180)then
      raise exception using errcode='22023',message='invalid_post_location';end if;
  end if;
  fingerprint:=jsonb_build_array(requested_text,requested_audience,requested_language);
  if total>0 or requested_location is not null then fingerprint:=fingerprint||jsonb_build_array(requested_photos,requested_location);end if;
  perform private.consume_feed_quota('post_create_request');
  perform pg_advisory_xact_lock(hashtextextended('feed-create:'||requested_id::text,0));
  select * into p from feed.posts where id=requested_id;
  if found then
    if p.author_id<>auth.uid()or p.creation_request<>fingerprint or p.deleted_at is not null then
      raise exception using errcode='23505',message='post_id_conflict';end if;
    return private.feed_post_json(p);
  end if;
  select * into d from feed.post_drafts where id=requested_id for update;
  if found and d.owner_id=auth.uid()and d.cancelled_at is null and d.published_at is null and d.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='photo_reservation_expired';end if;
  if found and(d.owner_id<>auth.uid()or d.cancelled_at is not null or d.published_at is not null or d.expires_at<=statement_timestamp())then
    raise exception using errcode='22023',message='draft_unavailable';end if;
  perform 1 from feed.photo_uploads where draft_id=requested_id order by id for update;
  if total>0 then
    select count(*)into attached from feed.photo_uploads u where u.draft_id=requested_id and u.id=any(requested_photos)and u.state='ready'
      and exists(select 1 from storage.objects where bucket_id='feed-media'and name=u.image_path)
      and exists(select 1 from storage.objects where bucket_id='feed-media'and name=u.thumbnail_path);
    if attached<>total or d.id is null then raise exception using errcode='22023',message='photos_not_ready';end if;
  end if;
  perform private.consume_feed_quota('post_create');
  insert into feed.posts(id,author_id,text,audience,language,creation_request,photo_count,latitude,longitude)
    values(requested_id,auth.uid(),requested_text,requested_audience,requested_language,fingerprint,total,lat,lon)returning * into p;
  update feed.photo_uploads u set state='attached',position=(selected.ordinality-1)::integer
    from unnest(requested_photos)with ordinality selected(id,ordinality)where u.draft_id=requested_id and u.id=selected.id;
  update feed.post_drafts set published_at=statement_timestamp()where id=requested_id;
  delete from media.cleanup_jobs where bucket='feed-media'and path in(
    select image_path from feed.photo_uploads where draft_id=requested_id and state='attached'
    union all select thumbnail_path from feed.photo_uploads where draft_id=requested_id and state='attached');
  return private.feed_post_json(p);
end $$;
notify pgrst,'reload schema';
