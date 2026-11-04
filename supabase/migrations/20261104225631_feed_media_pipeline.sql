-- Canonical photo lifecycle. Storage objects are mutated exclusively by its
-- API. Originals never become readable to clients; served images are re-encoded.
create schema media;
revoke all on schema media from public,anon,authenticated;
do $$ begin
  if not exists(select 1 from pg_roles where rolname='yap_feed_media_worker')then
    create role yap_feed_media_worker nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
  elsif exists(select 1 from pg_roles where rolname='yap_feed_media_worker'
    and(rolcanlogin or rolsuper or rolbypassrls or rolcreaterole or rolcreatedb))then
    raise exception 'Media worker role must be restricted NOLOGIN';
  end if;
end $$;
grant yap_feed_media_worker to authenticator;
grant usage on schema media,private,storage to yap_feed_media_worker;
grant select,insert,delete on storage.objects to yap_feed_media_worker;
grant select on storage.buckets to yap_feed_media_worker;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values
  ('feed-uploads','feed-uploads',false,5242880,array['image/jpeg','image/png']),
  ('feed-media','feed-media',false,5242880,array['image/jpeg']);

create table feed.post_drafts(
  id uuid primary key,
  owner_id uuid not null references public.profiles(id)on delete cascade,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp()+interval '1 hour',
  published_at timestamptz,
  cancelled_at timestamptz
);
create index feed_post_drafts_owner_idx on feed.post_drafts(owner_id,expires_at);
create index feed_post_drafts_expiry_idx on feed.post_drafts(expires_at)where published_at is null;
create table feed.photo_uploads(
  id uuid primary key,
  draft_id uuid not null references feed.post_drafts(id)on delete cascade,
  slot integer not null check(slot between 0 and 2),
  position integer check(position between 0 and 2),
  declared_bytes integer not null check(declared_bytes between 1 and 5242880),
  declared_mime text not null check(declared_mime in('image/jpeg','image/png')),
  source_path text not null unique,
  state text not null default 'waiting'check(state in('waiting','queued','processing','ready','attached','rejected')),
  created_at timestamptz not null default statement_timestamp(),
  available_at timestamptz not null default statement_timestamp(),
  lease uuid,
  locked_until timestamptz,
  attempts integer not null default 0 check(attempts between 0 and 8),
  failure_code text check(failure_code in('invalid_image','processing_failed')),
  image_path text unique,
  thumbnail_path text unique,
  width integer check(width between 1 and 2048),
  height integer check(height between 1 and 2048),
  image_bytes integer check(image_bytes between 1 and 5242880),
  thumbnail_bytes integer check(thumbnail_bytes between 1 and 5242880),
  sha256 text check(sha256~'^[a-f0-9]{64}$'),
  unique(draft_id,slot),
  check((lease is null)=(locked_until is null)),
  check(state not in('ready','attached')or(image_path is not null and thumbnail_path is not null and width is not null
    and height is not null and image_bytes is not null and thumbnail_bytes is not null and sha256 is not null))
);
create index feed_photo_jobs_ready_idx on feed.photo_uploads(available_at,id)where state in('queued','processing')and attempts<8;
create table media.cleanup_jobs(
  bucket text not null check(bucket in('feed-uploads','feed-media')),
  path text not null,
  available_at timestamptz not null default statement_timestamp(),
  lease uuid,
  locked_until timestamptz,
  attempts integer not null default 0 check(attempts between 0 and 8),
  primary key(bucket,path),
  check((lease is null)=(locked_until is null))
);
create index feed_media_cleanup_ready_idx on media.cleanup_jobs(available_at,bucket,path)where attempts<8;
create table private.feed_media_limits(
  user_id uuid not null references public.profiles(id)on delete cascade,
  operation text not null check(operation in('reserve','confirm','status','cancel')),
  started_at timestamptz not null,
  requests integer not null,
  primary key(user_id,operation)
);
alter table feed.post_drafts enable row level security;
alter table feed.photo_uploads enable row level security;
alter table media.cleanup_jobs enable row level security;
alter table private.feed_media_limits enable row level security;
revoke all on feed.post_drafts,feed.photo_uploads,media.cleanup_jobs,private.feed_media_limits
  from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;

create function private.consume_feed_media_quota(operation_name text)
returns void language plpgsql security definer set search_path='' as $$
declare accepted integer;
begin
  perform private.require_active_account();
  insert into private.feed_media_limits as q(user_id,operation,started_at,requests)
    values(auth.uid(),operation_name,statement_timestamp(),1)
  on conflict(user_id,operation)do update set
    started_at=case when q.started_at<=statement_timestamp()-interval '1 minute'then statement_timestamp()else q.started_at end,
    requests=case when q.started_at<=statement_timestamp()-interval '1 minute'then 1 else q.requests+1 end
  where q.started_at<=statement_timestamp()-interval '1 minute'or q.requests<60 returning requests into accepted;
  if accepted is null then raise exception using errcode='42901',message='feed_media_rate_limited';end if;
end $$;

create function private.queue_feed_media_delete(bucket_name text,object_path text,not_before timestamptz default statement_timestamp())
returns void language sql security definer set search_path='' as $$
  insert into media.cleanup_jobs as j(bucket,path,available_at)
    select bucket_name,object_path,not_before where object_path is not null
  on conflict(bucket,path)do update set available_at=least(j.available_at,excluded.available_at),
    attempts=case when j.lease is null then 0 else j.attempts end;
$$;

create function private.feed_photo_status(photo feed.photo_uploads)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object('id',photo.id,'slot',photo.slot,'state',case
    when photo.state in('queued','processing')and photo.attempts>=8 and(photo.locked_until is null or photo.locked_until<statement_timestamp())
      then 'failed'else photo.state end,'failure_code',photo.failure_code);
$$;

create function private.reserve_feed_photo_impl(requested_post uuid,requested_photo uuid,requested_bytes integer,requested_mime text)
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

create function private.confirm_feed_photo_impl(requested_photo uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype;
begin
  perform private.consume_feed_media_quota('confirm');
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

create function private.get_feed_photo_status_impl(requested_post uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d feed.post_drafts%rowtype; photos jsonb;
begin
  perform private.consume_feed_media_quota('status');
  select * into d from feed.post_drafts where id=requested_post and owner_id=auth.uid();
  if not found then raise exception using errcode='PT404',message='draft_not_found';end if;
  select coalesce(jsonb_agg(private.feed_photo_status(p)order by p.slot),'[]'::jsonb)into photos from feed.photo_uploads p where p.draft_id=d.id;
  return jsonb_build_object('post_id',d.id,'photos',photos,'expires_at',d.expires_at,'cancelled',d.cancelled_at is not null,'published',d.published_at is not null);
end $$;

create function private.cancel_feed_draft_impl(requested_post uuid)
returns void language plpgsql security definer set search_path='' as $$
declare d feed.post_drafts%rowtype; p record;
begin
  perform private.consume_feed_media_quota('cancel');
  select * into d from feed.post_drafts where id=requested_post and owner_id=auth.uid()for update;
  if not found or d.published_at is not null then raise exception using errcode='22023',message='draft_unavailable';end if;
  update feed.post_drafts set cancelled_at=coalesce(cancelled_at,statement_timestamp())where id=d.id;
  for p in select * from feed.photo_uploads where draft_id=d.id loop
    perform private.queue_feed_media_delete('feed-uploads',p.source_path,statement_timestamp()+interval '15 minutes');
    perform private.queue_feed_media_delete('feed-media',p.image_path,statement_timestamp()+interval '15 minutes');
    perform private.queue_feed_media_delete('feed-media',p.thumbnail_path,statement_timestamp()+interval '15 minutes');
  end loop;
end $$;

-- Operation-aware RLS deliberately denies listing, signing, copying and
-- overwriting. A signed URL would otherwise survive a later friendship/block.
create function private.feed_upload_allowed(object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from feed.photo_uploads p join feed.post_drafts d on d.id=p.draft_id
    where p.source_path=object_path and p.state='waiting'and d.owner_id=auth.uid()
      and d.published_at is null and d.cancelled_at is null and d.expires_at>statement_timestamp());
$$;
create function private.feed_media_read_allowed(object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles where id=auth.uid())
    and not private.is_account_globally_banned(auth.uid())and not private.is_account_pending_deletion(auth.uid())
    and exists(select 1 from feed.photo_uploads u join feed.posts p on p.id=u.draft_id
    where(object_path=u.image_path or object_path=u.thumbnail_path)and u.state='attached'
      and p.deleted_at is null and p.moderation_status='allowed'and private.feed_post_visible(auth.uid(),p.author_id,p.audience));
$$;
create function private.feed_media_worker_allowed(bucket_name text,object_path text,operation_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select case when operation_name='delete'then exists(select 1 from media.cleanup_jobs j
    where j.bucket=bucket_name and j.path=object_path and j.lease is not null and j.locked_until>statement_timestamp())
  else exists(select 1 from feed.photo_uploads p join feed.post_drafts d on d.id=p.draft_id
    where p.state='processing'and p.lease is not null and p.locked_until>statement_timestamp()
      and d.cancelled_at is null and d.published_at is null and d.expires_at>statement_timestamp()
      and not private.is_account_globally_banned(d.owner_id)and not private.is_account_pending_deletion(d.owner_id)
      and((bucket_name='feed-uploads'and operation_name='read'and p.source_path=object_path)
        or(bucket_name='feed-media'and object_path in(
          d.owner_id::text||'/'||p.draft_id::text||'/'||p.id::text||'/'||p.lease::text||'/image.jpg',
          d.owner_id::text||'/'||p.draft_id::text||'/'||p.id::text||'/'||p.lease::text||'/thumbnail.jpg'))))end;
$$;
create policy "Feed upload reservations"on storage.objects for insert to authenticated
  with check(bucket_id='feed-uploads'and storage.allow_only_operation('object.upload')and private.feed_upload_allowed(name));
create policy "Feed media authenticated reads"on storage.objects for select to authenticated
  using(bucket_id='feed-media'and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info'])
    and private.feed_media_read_allowed(name));
create policy "Feed media worker reads"on storage.objects for select to yap_feed_media_worker using(
  (storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.upload'])
    and private.feed_media_worker_allowed(bucket_id,name,'read'))
  or(storage.allow_any_operation(array['object.delete','object.delete_many'])and private.feed_media_worker_allowed(bucket_id,name,'delete')));
create policy "Feed media worker writes"on storage.objects for insert to yap_feed_media_worker
  with check(bucket_id='feed-media'and storage.allow_only_operation('object.upload')and private.feed_media_worker_allowed(bucket_id,name,'write'));
create policy "Feed media worker cleanup"on storage.objects for delete to yap_feed_media_worker
  using(private.feed_media_worker_allowed(bucket_id,name,'delete'));

create function media.contract()
returns jsonb language sql immutable set search_path='' as $$select '{"version":1,"processor":"jpeg-v1","max_bytes":5242880}'::jsonb;$$;
create function media.claim_photo(requested_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype; d feed.post_drafts%rowtype; prefix text;
begin
  if requested_lease is null then raise exception using errcode='22023',message='lease_required';end if;
  select u.* into p from feed.photo_uploads u join feed.post_drafts draft on draft.id=u.draft_id
    where u.state in('queued','processing')and u.attempts<8 and u.available_at<=statement_timestamp()
      and(u.locked_until is null or u.locked_until<=statement_timestamp())
      and draft.expires_at>statement_timestamp()and draft.cancelled_at is null and draft.published_at is null
      and not private.is_account_globally_banned(draft.owner_id)and not private.is_account_pending_deletion(draft.owner_id)
    order by u.available_at,u.id for update of u skip locked limit 1;
  if not found then return null;end if;
  select * into d from feed.post_drafts where id=p.draft_id;
  prefix:=d.owner_id::text||'/'||p.draft_id::text||'/'||p.id::text||'/'||requested_lease::text;
  update feed.photo_uploads set state='processing',lease=requested_lease,locked_until=statement_timestamp()+interval '2 minutes',
    attempts=attempts+1 where id=p.id;
  -- Register every attempted output before sending bytes. Failed/stale attempts
  -- therefore remain discoverable even if the process crashes before completion.
  perform private.queue_feed_media_delete('feed-media',prefix||'/image.jpg',statement_timestamp()+interval '17 minutes');
  perform private.queue_feed_media_delete('feed-media',prefix||'/thumbnail.jpg',statement_timestamp()+interval '17 minutes');
  return jsonb_build_object('id',p.id,'lease',requested_lease,'source_path',p.source_path,'declared_bytes',p.declared_bytes,
    'declared_mime',p.declared_mime,'image_path',prefix||'/image.jpg','thumbnail_path',prefix||'/thumbnail.jpg');
end $$;

create function media.complete_photo(requested_id uuid,requested_lease uuid,result jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype; d feed.post_drafts%rowtype; prefix text;
begin
  select * into p from feed.photo_uploads where id=requested_id and state='processing'and lease=requested_lease
    and locked_until>clock_timestamp()for update;
  if not found then return false;end if;
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
create function media.fail_photo(requested_id uuid,requested_lease uuid,invalid_image boolean)
returns void language plpgsql security definer set search_path='' as $$
declare p feed.photo_uploads%rowtype;
begin
  update feed.photo_uploads set state=case when invalid_image then 'rejected'else 'queued'end,
    failure_code=case when invalid_image then 'invalid_image'else 'processing_failed'end,lease=null,locked_until=null,
    available_at=statement_timestamp()+make_interval(secs=>least(300,power(2,attempts)::integer))
  where id=requested_id and lease=requested_lease and locked_until>statement_timestamp()returning * into p;
  if found and invalid_image then perform private.queue_feed_media_delete('feed-uploads',p.source_path);end if;
end $$;

create function private.feed_media_is_retained(bucket_name text,object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from feed.photo_uploads u join feed.post_drafts d on d.id=u.draft_id
    left join feed.posts post on post.id=d.id
    where(bucket_name='feed-uploads'and u.source_path=object_path and u.state in('waiting','queued','processing')
      and d.cancelled_at is null and d.expires_at>statement_timestamp())
    or(bucket_name='feed-media'and object_path in(u.image_path,u.thumbnail_path)
      and u.state='attached'and post.deleted_at is null and post.id is not null));
$$;
create function media.claim_cleanup(requested_lease uuid)
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
      where j.path in(u.image_path,u.thumbnail_path)and u.state='ready'and d.expires_at>statement_timestamp()and d.cancelled_at is null)then
      update media.cleanup_jobs set available_at=statement_timestamp()+interval '1 hour'where bucket=j.bucket and path=j.path;
      continue;
    end if;
    update media.cleanup_jobs set lease=requested_lease,locked_until=statement_timestamp()+interval '1 minute',attempts=attempts+1
      where bucket=j.bucket and path=j.path;
    return jsonb_build_object('bucket',j.bucket,'path',j.path,'lease',requested_lease);
  end loop;
  return null;
end $$;
create function media.complete_cleanup(requested_bucket text,requested_path text,requested_lease uuid,succeeded boolean)
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
create function private.cleanup_deleted_feed_photo()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform private.queue_feed_media_delete('feed-uploads',old.source_path,statement_timestamp()+interval '15 minutes');
  perform private.queue_feed_media_delete('feed-media',old.image_path,statement_timestamp()+interval '15 minutes');
  perform private.queue_feed_media_delete('feed-media',old.thumbnail_path,statement_timestamp()+interval '15 minutes');
  return null;
end $$;
create trigger feed_photo_deletion_cleanup after delete on feed.photo_uploads for each row execute function private.cleanup_deleted_feed_photo();
create function private.cleanup_deleted_feed_post_media()
returns trigger language plpgsql security definer set search_path='' as $$
declare p record;
begin
  if tg_op='UPDATE'and new.deleted_at is null then return null;end if;
  for p in select * from feed.photo_uploads where draft_id=old.id loop
    perform private.queue_feed_media_delete('feed-media',p.image_path);
    perform private.queue_feed_media_delete('feed-media',p.thumbnail_path);
  end loop;
  return null;
end $$;
create trigger feed_post_media_cleanup after delete or update of deleted_at on feed.posts
  for each row execute function private.cleanup_deleted_feed_post_media();
create function media.maintenance(retry_failed boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
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

alter table feed.posts add column photo_count integer not null default 0 check(photo_count between 0 and 3),
  add column latitude double precision,add column longitude double precision,
  add constraint feed_post_location_pair check((latitude is null)=(longitude is null)),
  add constraint feed_post_location_range check(latitude between -90 and 90 and longitude between -180 and 180);
alter table feed.posts drop constraint posts_text_check;
alter table feed.posts add constraint posts_content_check check(char_length(text)<=1000 and
  (text=''or text~'[^[:space:]]')and(text<>''or photo_count>0));

create function private.feed_post_location(p feed.posts)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare precise boolean; nearby boolean;
begin
  if p.latitude is null then return null;end if;
  precise:=auth.uid()=p.author_id or(exists(select 1 from public.friendships f
    where f.user_one_id=least(auth.uid(),p.author_id)and f.user_two_id=greatest(auth.uid(),p.author_id))
    and coalesce((select share_precise_location from private.search_privacy_settings where user_id=p.author_id),true)
    and not exists(select 1 from private.precise_location_exclusions where owner_user_id=p.author_id and viewer_user_id=auth.uid()));
  select 6371000*2*asin(sqrt(least(1.0,power(sin(radians(l.latitude-p.latitude)/2),2)
    +cos(radians(l.latitude))*cos(radians(p.latitude))*power(sin(radians(l.longitude-p.longitude)/2),2))))<=50000
    into nearby from public.user_locations l where l.user_id=auth.uid()and l.updated_at>statement_timestamp()-interval '12 hours';
  if precise then return jsonb_build_object('latitude',p.latitude,'longitude',p.longitude,'nearby',coalesce(nearby,false));end if;
  if coalesce(nearby,false)then return jsonb_build_object('nearby',true);end if;
  return null;
end $$;
create or replace function private.feed_post_json(p feed.posts)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',p.id,'author_id',p.author_id,'text',p.text,'audience',p.audience,'language',p.language,
    'version',p.version,'created_at',p.created_at,'updated_at',p.updated_at,'location',private.feed_post_location(p),
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'bucket','feed-media','path',u.image_path,
      'thumbnail_path',u.thumbnail_path,'width',u.width,'height',u.height,'bytes',u.image_bytes,'sha256',u.sha256,'mime','image/jpeg')order by u.position)
      from feed.photo_uploads u where u.draft_id=p.id and u.state='attached'),'[]'::jsonb));
$$;

create function private.publish_feed_post_impl(requested_id uuid,requested_text text,requested_audience text,requested_language text,
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
create or replace function private.create_feed_post_impl(requested_id uuid,requested_text text,requested_audience text,requested_language text)
returns jsonb language sql security definer set search_path='' as $$
  select private.publish_feed_post_impl(requested_id,requested_text,requested_audience,requested_language,'{}'::uuid[],null);
$$;

create function public.reserve_feed_photo(requested_post uuid,requested_photo uuid,requested_bytes integer,requested_mime text)
returns jsonb language sql security invoker set search_path='' as $$select private.reserve_feed_photo_impl(requested_post,requested_photo,requested_bytes,requested_mime);$$;
create function public.confirm_feed_photo(requested_photo uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.confirm_feed_photo_impl(requested_photo);$$;
create function public.get_feed_photo_status(requested_post uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.get_feed_photo_status_impl(requested_post);$$;
create function public.cancel_feed_draft(requested_post uuid)
returns void language sql security invoker set search_path='' as $$select private.cancel_feed_draft_impl(requested_post);$$;
create function public.publish_feed_post(requested_id uuid,requested_text text default '',requested_audience text default 'public',
  requested_language text default 'ru',requested_photos uuid[]default '{}',requested_location jsonb default null)
returns jsonb language sql security invoker set search_path='' as $$
  select private.publish_feed_post_impl(requested_id,requested_text,requested_audience,requested_language,requested_photos,requested_location);
$$;

revoke all on all functions in schema media from public,anon,authenticated;
grant execute on function media.contract(),media.claim_photo(uuid),media.complete_photo(uuid,uuid,jsonb),media.fail_photo(uuid,uuid,boolean),
  media.claim_cleanup(uuid),media.complete_cleanup(text,text,uuid,boolean),media.maintenance(boolean)to yap_feed_media_worker;
revoke all on function private.consume_feed_media_quota(text),private.queue_feed_media_delete(text,text,timestamptz),
  private.feed_photo_status(feed.photo_uploads),private.feed_upload_allowed(text),private.feed_media_read_allowed(text),
  private.feed_media_worker_allowed(text,text,text),private.feed_media_is_retained(text,text),private.cleanup_deleted_feed_photo(),
  private.cleanup_deleted_feed_post_media(),private.feed_post_location(feed.posts)
  from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.feed_upload_allowed(text),private.feed_media_read_allowed(text)to authenticated;
grant execute on function private.feed_media_worker_allowed(text,text,text)to yap_feed_media_worker;
do $$declare signature text;impl text;begin
  foreach signature in array array['reserve_feed_photo(uuid,uuid,integer,text)','confirm_feed_photo(uuid)',
    'get_feed_photo_status(uuid)','cancel_feed_draft(uuid)','publish_feed_post(uuid,text,text,text,uuid[],jsonb)']loop
    impl:=replace(signature,'(','_impl(');
    execute 'revoke all on function public.'||signature||',private.'||impl||' from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker';
    execute 'grant execute on function public.'||signature||',private.'||impl||' to authenticated';
  end loop;
end $$;
notify pgrst,'reload schema';

-- Empty captions have no text embedding. Photo feedback still supplies bounded author affinity.
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
      done_at = null, attempts = 0, available_at = statement_timestamp(), lease = null, locked_until = null, last_error = null;
  end if;
  return null;
end $$;
create or replace function private.edit_feed_post_impl(requested_id uuid, expected_version integer, requested_text text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p feed.posts%rowtype;
begin
  perform private.require_active_account();
  if requested_text is null or char_length(requested_text)>1000 or (requested_text<>''and requested_text !~ '[^[:space:]]')
    or expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'invalid_post';
  end if;
  perform private.consume_feed_quota('post_edit_request');
  select * into p from feed.posts where id = requested_id and author_id = auth.uid()
    and deleted_at is null and moderation_status = 'allowed' for update;
  if not found then raise exception using errcode = 'P0002', message = 'post_not_found'; end if;
  if requested_text=''and p.photo_count=0 then raise exception using errcode='22023',message='empty_post';end if;
  if p.version <> expected_version then
    raise exception using errcode = '40001', message = 'post_version_conflict';
  end if;
  if p.text = requested_text then return private.feed_post_json(p); end if;
  perform private.consume_feed_quota('post_edit');
  update feed.posts set text = requested_text where id = p.id returning * into p;
  return private.feed_post_json(p);
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
      and created_at>statement_timestamp()-interval '7 days'order by created_at desc,id limit 1000)p left join recsys.post_statistics st on st.post_id=p.id
      where p.created_at>statement_timestamp()-interval '7 days' and p.deleted_at is null and p.moderation_status='allowed'
      and coalesce(st.impressions,0)<20 and not exists(select 1 from seen where seen.post_id=p.id)
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
  ), ids as materialized(select id,array_agg(distinct source order by source) sources from pool group by id),
  authors as materialized(
    select distinct p.author_id,p.audience from ids join feed.posts p on p.id=ids.id
  ), allowed as materialized(select a.* from authors a where private.feed_post_visible(viewer,a.author_id,a.audience)),
  candidates as (
    select p.id,p.author_id,p.version,p.created_at,coalesce(em.embedding::text,'') vector,ids.sources,
      (exists(select 1 from social where author_id=p.author_id)or exists(select 1 from affinity where author_id=p.author_id)) social,coalesce(st.impressions,0)impressions,
      coalesce(st.likes,0)likes,seen.at is not null seen
    from ids join feed.posts p on p.id=ids.id join allowed a on a.author_id=p.author_id and a.audience=p.audience
    left join recsys.post_embeddings em on em.post_id=p.id and em.post_version=p.version and em.model=requested_model
    left join recsys.post_statistics st on st.post_id=p.id left join seen on seen.post_id=p.id
    where p.author_id<>viewer and p.deleted_at is null and p.moderation_status='allowed'
      and p.created_at>statement_timestamp()-interval '7 days'
      and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
      and not exists(select 1 from recsys.semantic_suppressions h where h.user_id=viewer and h.post_id=p.id)
    order by p.id limit 1200
  )select coalesce(jsonb_agg(to_jsonb(c)order by c.id),'[]'::jsonb)into result from candidates c;
  return result;
end $$;
