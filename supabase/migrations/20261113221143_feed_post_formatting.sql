-- Formatting offsets refer to the exact stored text in Unicode code points.
alter table feed.posts add column format_spans jsonb not null default '[]'::jsonb;

create function private.normalize_feed_formatting(body text, formatting jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  span jsonb;
  spans jsonb;
  start_at integer;
  end_at integer;
  style text;
  body_length integer := char_length(body);
begin
  if formatting is null then return '[]'::jsonb; end if;
  if jsonb_typeof(formatting) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_post_formatting';
  end if;
  if formatting - array['version','spans'] <> '{}'::jsonb
    or formatting->'version' is distinct from '1'::jsonb
    or jsonb_typeof(formatting->'spans') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'invalid_post_formatting';
  end if;
  spans := formatting->'spans';
  if jsonb_array_length(spans) > 128 then
    raise exception using errcode = '22023', message = 'invalid_post_formatting';
  end if;
  for span in select value from jsonb_array_elements(spans) loop
    if jsonb_typeof(span) <> 'object' then
      raise exception using errcode = '22023', message = 'invalid_post_formatting';
    end if;
    if span - array['start','end','style'] <> '{}'::jsonb
      or jsonb_typeof(span->'start') is distinct from 'number'
      or jsonb_typeof(span->'end') is distinct from 'number'
      or coalesce(span->>'start','') !~ '^(0|[1-9][0-9]{0,3})$'
      or coalesce(span->>'end','') !~ '^[1-9][0-9]{0,3}$'
      or coalesce(span->>'style','') not in ('bold','italic','underline','strikethrough')
      or jsonb_typeof(span->'style') is distinct from 'string' then
      raise exception using errcode = '22023', message = 'invalid_post_formatting';
    end if;
    start_at := (span->>'start')::integer;
    end_at := (span->>'end')::integer;
    if end_at <= start_at or end_at > body_length then
      raise exception using errcode = '22023', message = 'invalid_post_formatting';
    end if;
  end loop;
  if exists (
    select 1 from (
      select (value->>'start')::integer as start_at,
        lag((value->>'end')::integer) over (
          partition by value->>'style' order by (value->>'start')::integer, (value->>'end')::integer
        ) as previous_end
      from jsonb_array_elements(spans)
    ) ordered_spans where ordered_spans.start_at < ordered_spans.previous_end
  ) then
    raise exception using errcode = '22023', message = 'invalid_post_formatting';
  end if;
  select coalesce(jsonb_agg(value order by (value->>'start')::integer, (value->>'end')::integer, (value->>'style') collate "C"), '[]'::jsonb)
    into spans from jsonb_array_elements(spans);
  return spans;
end $$;

revoke all on function private.normalize_feed_formatting(text,jsonb) from public, anon, authenticated;

create or replace function private.base_feed_post_json(p feed.posts)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'author_id', p.author_id, 'text', p.text,
    'formatting', jsonb_build_object('version', 1, 'spans', p.format_spans),
    'audience', p.audience, 'language', p.language, 'version', p.version,
    'created_at', p.created_at, 'updated_at', p.updated_at, 'edited', p.version > 1,
    'location', private.feed_post_location(p),
    'author', jsonb_build_object('id', a.id, 'username', a.username,
      'display_name', a.display_name, 'avatar_url', a.avatar_url,
      'avatar_storage_path', a.avatar_storage_path, 'avatar_updated_at', a.avatar_updated_at),
    'like_count', coalesce(st.likes, 0),
    'view_count', coalesce(st.impressions, 0),
    'photos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'bucket', 'feed-media', 'path', u.image_path,
      'thumbnail_path', u.thumbnail_path, 'width', u.width, 'height', u.height,
      'bytes', u.image_bytes, 'sha256', u.sha256, 'mime', 'image/jpeg') order by u.position)
      from feed.photo_uploads u where u.draft_id = p.id and u.state = 'attached'), '[]'::jsonb)
  )
  from public.profiles a
  left join recsys.post_statistics st on st.post_id = p.id
  where a.id = p.author_id;
$$;

create or replace function private.version_feed_post()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.version := old.version + case when new.text is distinct from old.text
    or new.format_spans is distinct from old.format_spans then 1 else 0 end;
  new.updated_at := statement_timestamp();
  return new;
end $$;

create or replace function private.queue_feed_post_index()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.text is not distinct from old.text
    and new.format_spans is not distinct from old.format_spans
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

-- Embeddings and deliveries are keyed by content version. Keep format-only
-- edits on the same invalidation and indexing path as text edits.
drop trigger feed_post_index_outbox on feed.posts;
create trigger feed_post_index_outbox after insert or update of text, format_spans, moderation_status, deleted_at
  on feed.posts for each row execute function private.queue_feed_post_index();

create function private.publish_feed_post_impl(requested_id uuid,requested_text text,requested_audience text,requested_language text,
  requested_photos uuid[],requested_location jsonb, requested_formatting jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.posts%rowtype; d feed.post_drafts%rowtype; total integer; attached integer; lat float8; lon float8; fingerprint jsonb; spans jsonb;
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
  spans:=private.normalize_feed_formatting(requested_text,requested_formatting);
  fingerprint:=jsonb_build_array(requested_text,requested_audience,requested_language);
  if total>0 or requested_location is not null then fingerprint:=fingerprint||jsonb_build_array(requested_photos,requested_location);end if;
  if spans <> '[]'::jsonb then fingerprint:=fingerprint||jsonb_build_array(spans);end if;
  perform private.consume_feed_quota('post_create_request');
  perform pg_advisory_xact_lock(hashtextextended('feed-create:'||requested_id::text,0));
  if exists(select 1 from feed.reposts where id=requested_id)then raise exception using errcode='23505',message='post_id_conflict';end if;
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
  insert into feed.posts(id,author_id,text,audience,language,creation_request,photo_count,latitude,longitude,format_spans)
    values(requested_id,auth.uid(),requested_text,requested_audience,requested_language,fingerprint,total,lat,lon,spans)returning * into p;
  update feed.photo_uploads u set state='attached',position=(selected.ordinality-1)::integer
    from unnest(requested_photos)with ordinality selected(id,ordinality)where u.draft_id=requested_id and u.id=selected.id;
  update feed.post_drafts set published_at=statement_timestamp()where id=requested_id;
  delete from media.cleanup_jobs where bucket='feed-media'and path in(
    select image_path from feed.photo_uploads where draft_id=requested_id and state='attached'
    union all select thumbnail_path from feed.photo_uploads where draft_id=requested_id and state='attached');
  return private.feed_post_json(p);
end $$;

create function private.edit_feed_post_impl(requested_id uuid, expected_version integer, requested_text text, requested_formatting jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p feed.posts%rowtype; spans jsonb;
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
  spans := case when requested_formatting is null and p.text = requested_text
    then p.format_spans else private.normalize_feed_formatting(requested_text, requested_formatting) end;
  if p.text = requested_text and p.format_spans = spans then return private.feed_post_json(p); end if;
  perform private.consume_feed_quota('post_edit');
  update feed.posts set text = requested_text, format_spans = spans where id = p.id returning * into p;
  return private.feed_post_json(p);
end $$;

create function private.create_feed_repost_impl(requested_id uuid,requested_original uuid,requested_text text,requested_audience text,requested_language text, requested_formatting jsonb)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;original feed.posts%rowtype;r feed.reposts%rowtype;depth integer:=0; spans jsonb;
 fingerprint jsonb:=jsonb_build_array(requested_original,requested_text,requested_audience,requested_language);
begin
 perform private.require_social_account();perform private.consume_feed_quota('post_create_request');
 if requested_id is null or requested_original is null or requested_id=requested_original or requested_text is null or char_length(requested_text)>1000
 or(requested_text<>''and requested_text!~'[^[:space:]]')or requested_audience is null or requested_audience not in('public','friends')
 or requested_language is null or requested_language not in('ru','en')then raise exception using errcode='22023',message='invalid_repost';end if;
 spans:=private.normalize_feed_formatting(requested_text,requested_formatting);
 if spans <> '[]'::jsonb then fingerprint:=fingerprint||jsonb_build_array(spans);end if;
 perform private.lock_recommendation_user(auth.uid());
 perform pg_advisory_xact_lock(hashtextextended('feed-create:'||requested_id::text,0));
 select * into r from feed.reposts where id=requested_id;
 if found then
  if r.author_id<>auth.uid()or r.creation_request<>fingerprint or r.deleted_at is not null then raise exception using errcode='23505',message='repost_id_conflict';end if;
 else
  if exists(select 1 from feed.posts where id=requested_id)or exists(select 1 from feed.post_drafts where id=requested_id)then
   raise exception using errcode='23505',message='post_id_conflict';end if;
  select * into original from feed.posts where id=requested_original for share;
  if not found or not private.feed_post_accessible(auth.uid(),original)then raise exception using errcode='PT404',message='post_not_found';end if;
  p:=original;
  while p.is_repost loop
   depth:=depth+1;if depth>=4 then raise exception using errcode='22023',message='repost_depth_exceeded';end if;
   select * into p from feed.posts where id=p.original_post_id for share;
  end loop;
  perform private.consume_feed_quota('post_create');
  if requested_text<>''then
   insert into feed.posts(id,author_id,text,audience,language,creation_request,is_repost,original_post_id,format_spans)
   values(requested_id,auth.uid(),requested_text,requested_audience,requested_language,fingerprint,true,original.id,spans);
  end if;
  insert into feed.reposts(id,author_id,original_post_id,original_version,post_id,audience,creation_request)
  values(requested_id,auth.uid(),original.id,original.version,case when requested_text<>''then requested_id else null end,requested_audience,fingerprint)returning * into r;
 end if;
 select * into original from feed.posts where id=r.original_post_id;
 if not private.feed_post_accessible(auth.uid(),original)then raise exception using errcode='PT404',message='post_not_found';end if;
 return jsonb_build_object('id',r.id,'post_id',r.post_id,'original_post_id',r.original_post_id,'version',r.version,'created_at',r.created_at,'is_quote',r.post_id is not null);
end $$;

-- Keep the existing signatures for clients and SQL callers that omit formatting.
create or replace function private.publish_feed_post_impl(requested_id uuid, requested_text text,
  requested_audience text, requested_language text, requested_photos uuid[], requested_location jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select private.publish_feed_post_impl(requested_id, requested_text, requested_audience,
    requested_language, requested_photos, requested_location, null);
$$;

create or replace function private.edit_feed_post_impl(requested_id uuid, expected_version integer, requested_text text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.edit_feed_post_impl(requested_id, expected_version, requested_text, null);
$$;

create or replace function private.create_feed_repost_impl(requested_id uuid, requested_original uuid,
  requested_text text, requested_audience text, requested_language text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.create_feed_repost_impl(requested_id, requested_original, requested_text,
    requested_audience, requested_language, null);
$$;

-- Different arities preserve existing positional SQL calls and named RPC calls.
create function public.publish_feed_post(requested_id uuid, requested_text text,
  requested_audience text, requested_language text, requested_photos uuid[],
  requested_location jsonb, requested_formatting jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.publish_feed_post_impl(requested_id, requested_text, requested_audience,
    requested_language, requested_photos, requested_location, requested_formatting);
$$;

create function public.edit_feed_post(requested_id uuid, expected_version integer, requested_text text, requested_formatting jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.edit_feed_post_impl(requested_id, expected_version, requested_text, requested_formatting);
$$;

create function public.create_feed_repost(requested_id uuid, requested_original uuid,
  requested_text text, requested_audience text, requested_language text, requested_formatting jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.create_feed_repost_impl(requested_id, requested_original, requested_text,
    requested_audience, requested_language, requested_formatting);
$$;

revoke all on function
  private.publish_feed_post_impl(uuid,text,text,text,uuid[],jsonb,jsonb),
  private.edit_feed_post_impl(uuid,integer,text,jsonb),
  private.create_feed_repost_impl(uuid,uuid,text,text,text,jsonb),
  public.publish_feed_post(uuid,text,text,text,uuid[],jsonb,jsonb),
  public.edit_feed_post(uuid,integer,text,jsonb),
  public.create_feed_repost(uuid,uuid,text,text,text,jsonb)
from public, anon, authenticated;
grant execute on function
  private.publish_feed_post_impl(uuid,text,text,text,uuid[],jsonb,jsonb),
  private.edit_feed_post_impl(uuid,integer,text,jsonb),
  private.create_feed_repost_impl(uuid,uuid,text,text,text,jsonb),
  public.publish_feed_post(uuid,text,text,text,uuid[],jsonb,jsonb),
  public.edit_feed_post(uuid,integer,text,jsonb),
  public.create_feed_repost(uuid,uuid,text,text,text,jsonb)
to authenticated;

notify pgrst, 'reload schema';
