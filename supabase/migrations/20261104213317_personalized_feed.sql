-- Personalized text feed. All client access remains behind checked Supabase
-- RPCs; only job-scoped internal functions are granted to the Go processor.
create table recsys.user_states (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  epoch integer not null default 1 check (epoch > 0),
  revision bigint not null default 1,
  processed_revision bigint not null default 0,
  profile_complete boolean not null default false,
  current_snapshot uuid,
  prepared_at timestamptz,
  reset_at timestamptz not null default '-infinity',
  active_until timestamptz not null default statement_timestamp() + interval '1 day'
);
create table recsys.refresh_jobs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  target_revision bigint not null,
  available_at timestamptz not null default statement_timestamp(),
  lease uuid,
  locked_until timestamptz,
  attempts integer not null default 0 check (attempts between 0 and 8),
  last_error text check (last_error = 'processing_failed'),
  check ((lease is null) = (locked_until is null))
);
create index recsys_user_states_inactive_idx on recsys.user_states(active_until,user_id);
create index recsys_refresh_jobs_ready_idx on recsys.refresh_jobs (available_at, user_id) where attempts < 8;
create table recsys.interest_clusters (
  user_id uuid not null references public.profiles(id) on delete cascade,
  epoch integer not null,
  cluster integer not null check (cluster between 0 and 7),
  model text not null,
  negative boolean not null,
  weight double precision not null check (weight > 0 and weight < 10000),
  embedding extensions.vector(384) not null check (extensions.vector_norm(embedding) between .999 and 1.001),
  updated_at timestamptz not null,
  primary key (user_id, cluster)
);
create table recsys.feed_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  epoch integer not null,
  revision bigint not null,
  model text not null,
  embedding_model text not null,
  features_at timestamptz not null default statement_timestamp(),
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp() + interval '20 minutes'
);
create index recsys_feed_snapshots_expiry_idx on recsys.feed_snapshots (expires_at, id);
create index recsys_feed_snapshots_user_idx on recsys.feed_snapshots (user_id, created_at desc);
create table recsys.feed_snapshot_items (
  snapshot_id uuid not null references recsys.feed_snapshots(id) on delete cascade,
  position integer not null check (position between 0 and 199),
  post_id uuid not null references feed.posts(id) on delete cascade,
  post_version integer not null,
  features double precision[] not null default '{}',
  score double precision not null default 0 check (score between -1000 and 1000),
  reasons text[] not null default '{}',
  sources text[] not null default '{}',
  primary key (snapshot_id, position),
  unique (snapshot_id, post_id)
);
create index recsys_feed_snapshot_items_post_idx on recsys.feed_snapshot_items (post_id);
create table recsys.deliveries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references feed.posts(id) on delete cascade,
  post_version integer not null,
  epoch integer not null,
  surface text not null check (surface in ('for_you', 'direct', 'friends', 'nearby')),
  snapshot_id uuid,
  position integer,
  model text not null,
  embedding_model text not null,
  features double precision[] not null default '{}',
  features_at timestamptz not null default statement_timestamp(),
  delivered_at timestamptz not null default statement_timestamp(),
  valid_until timestamptz not null default statement_timestamp() + interval '20 minutes',
  qualified_at timestamptz,
  active_ms integer not null default 0 check (active_ms between 0 and 120000),
  opened boolean not null default false,
  unique (user_id, snapshot_id, position)
);
create index recsys_deliveries_cleanup_idx on recsys.deliveries (delivered_at, id);
create index recsys_deliveries_post_idx on recsys.deliveries(post_id);
create table recsys.telemetry_events (
  user_id uuid not null references public.profiles(id) on delete cascade,
  id uuid not null,
  delivery_id uuid not null references recsys.deliveries(id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (user_id, id)
);
create table recsys.daily_exposures (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references feed.posts(id) on delete cascade,
  day_utc date not null,
  post_version integer not null,
  epoch integer not null,
  last_seen_at timestamptz not null default statement_timestamp(),
  engaged_at timestamptz,
  active_ms integer not null default 0 check (active_ms between 0 and 120000),
  opened boolean not null default false,
  primary key (user_id, post_id, day_utc)
);
create index recsys_telemetry_delivery_idx on recsys.telemetry_events(delivery_id);
create index recsys_daily_exposures_post_idx on recsys.daily_exposures(post_id);
create index recsys_daily_exposures_recent_idx on recsys.daily_exposures (user_id, last_seen_at desc, post_id);
create index recsys_daily_exposures_cleanup_idx on recsys.daily_exposures (day_utc, user_id, post_id);
create table feed.post_likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references feed.posts(id) on delete cascade,
  post_version integer not null,
  epoch integer not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (user_id, post_id)
);
create index feed_post_likes_post_idx on feed.post_likes (post_id, user_id);
create table recsys.post_statistics (
  post_id uuid primary key references feed.posts(id) on delete cascade,
  likes bigint not null default 0 check (likes >= 0),
  impressions bigint not null default 0 check (impressions >= 0),
  quality double precision generated always as ((likes+1)::float8/(impressions+20)) stored
);
create index recsys_post_statistics_quality_idx on recsys.post_statistics(quality desc,post_id);
create table recsys.semantic_suppressions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references feed.posts(id) on delete cascade,
  post_version integer not null,
  epoch integer not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (user_id, post_id)
);
create index recsys_semantic_suppressions_post_idx on recsys.semantic_suppressions(post_id);
create table recsys.hidden_authors (
  user_id uuid not null references public.profiles(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  primary key (user_id, author_id),
  check (user_id <> author_id)
);
create table recsys.action_requests (
  user_id uuid not null references public.profiles(id) on delete cascade,
  id uuid not null,
  payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  primary key (user_id, id)
);
create table recsys.post_action_versions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references feed.posts(id) on delete cascade,
  version bigint not null check(version>0),
  primary key(user_id,post_id)
);
create index recsys_post_action_versions_post_idx on recsys.post_action_versions(post_id);
create index recsys_action_requests_cleanup_idx on recsys.action_requests (created_at, user_id, id);

-- All tables, including non-exposed ones, fail closed for raw client access.
do $$ declare r record; begin
  for r in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('feed','recsys') and c.relkind='r' loop
    execute format('alter table %I.%I enable row level security',r.nspname,r.relname);
    execute format('revoke all on table %I.%I from public,anon,authenticated,yap_recommendation_worker',r.nspname,r.relname);
  end loop;
end $$;

alter table private.feed_operation_limits drop constraint feed_operation_limits_operation_check;
alter table private.feed_operation_limits add constraint feed_operation_limits_operation_check check (
  operation in ('post_create','post_edit','post_delete','post_read','post_create_request','post_edit_request','post_delete_request',
    'recommendation_read','feed_events','feed_action','feed_preferences')
);

create or replace function private.consume_feed_quota(requested_operation text)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid(); minute_limit integer; daily_limit integer;
  accepted integer; recent_count integer; today date := (statement_timestamp() at time zone 'UTC')::date;
begin
  if viewer is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if requested_operation='post_create' then
    -- The create RPC has already acquired the per-user post_create_request
    -- quota row lock. Count soft-deleted posts too: deletion cannot evade this.
    select count(*) into recent_count from (select 1 from feed.posts where author_id=viewer
      and created_at>statement_timestamp()-interval '1 hour' limit 12) recent;
    if recent_count>=12 then raise exception using errcode='42901',message='post_hourly_rate_limited'; end if;
    insert into private.feed_operation_limits as l(user_id,operation,window_started_at,request_count,day_utc,day_count)
      values(viewer,requested_operation,statement_timestamp(),recent_count+1,today,1)
    on conflict(user_id,operation) do update set request_count=recent_count+1,window_started_at=statement_timestamp(),
      day_utc=today,day_count=case when l.day_utc<today then 1 else l.day_count+1 end;
    return;
  end if;
  case requested_operation
    when 'post_edit' then minute_limit:=6; daily_limit:=100;
    when 'post_delete' then minute_limit:=12; daily_limit:=100;
    when 'post_read' then minute_limit:=60; daily_limit:=86400;
    when 'post_create_request' then minute_limit:=60; daily_limit:=86400;
    when 'post_edit_request' then minute_limit:=60; daily_limit:=86400;
    when 'post_delete_request' then minute_limit:=60; daily_limit:=86400;
    when 'recommendation_read' then minute_limit:=60; daily_limit:=86400;
    when 'feed_events' then minute_limit:=30; daily_limit:=10000;
    when 'feed_action' then minute_limit:=120; daily_limit:=20000;
    when 'feed_preferences' then minute_limit:=30; daily_limit:=1000;
    else raise exception using errcode='22023',message='invalid_feed_operation';
  end case;
  insert into private.feed_operation_limits as l(user_id,operation,window_started_at,request_count,day_utc,day_count)
    values(viewer,requested_operation,statement_timestamp(),1,today,1)
  on conflict(user_id,operation) do update set
    window_started_at=case when l.window_started_at<=statement_timestamp()-interval '1 minute' then statement_timestamp() else l.window_started_at end,
    request_count=case when l.window_started_at<=statement_timestamp()-interval '1 minute' then 1 else l.request_count+1 end,
    day_utc=today,day_count=case when l.day_utc<today then 1 else l.day_count+1 end
  where (l.window_started_at<=statement_timestamp()-interval '1 minute' or l.request_count<minute_limit)
    and (l.day_utc<today or l.day_count<daily_limit)
  returning request_count into accepted;
  if accepted is null then raise exception using errcode='42901',message='feed_rate_limited'; end if;
end $$;

create function private.lock_recommendation_user(viewer uuid)
returns recsys.user_states language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype;
begin
  insert into recsys.user_states(user_id)values(viewer)on conflict do nothing;
  select * into s from recsys.user_states where user_id=viewer for update;
  if s.active_until<statement_timestamp()+interval '1 hour' then
    update recsys.user_states set active_until=statement_timestamp()+interval '1 day'where user_id=viewer returning * into s;
  end if;
  return s;
end $$;

create function private.queue_recommendation_refresh(viewer uuid, version bigint, immediate boolean default false)
returns void language sql security definer set search_path='' as $$
  insert into recsys.refresh_jobs as j(user_id,target_revision,available_at)
    values(viewer,version,statement_timestamp()+case when immediate then interval '0 seconds' else interval '1 second' end)
  on conflict(user_id) do update set target_revision=greatest(j.target_revision,excluded.target_revision),
    available_at=least(j.available_at,excluded.available_at),
    attempts=case when excluded.target_revision>j.target_revision then 0 else j.attempts end;
$$;

create function private.recommendation_post_allowed(viewer uuid, p feed.posts)
returns boolean language sql stable security definer set search_path='' as $$
  select p.author_id<>viewer and p.deleted_at is null and p.moderation_status='allowed'
    and private.feed_post_visible(viewer,p.author_id,p.audience)
    and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
    and not exists(select 1 from recsys.semantic_suppressions h where h.user_id=viewer and h.post_id=p.id);
$$;

create or replace function private.get_feed_post_impl(requested_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.posts%rowtype; s recsys.user_states%rowtype; delivery uuid; delivery_until timestamptz;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('post_read');
  s:=private.lock_recommendation_user(auth.uid());
  select * into p from feed.posts where id=requested_id and deleted_at is null and moderation_status='allowed'
    and private.feed_post_visible(auth.uid(),author_id,audience);
  if not found then return null; end if;
  insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
    values(auth.uid(),p.id,p.version,s.epoch,'direct','direct-v1',
      'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query') returning id,valid_until into delivery,delivery_until;
  return private.feed_post_json(p)||jsonb_build_object('delivery_id',delivery,'delivery_expires_at',delivery_until,'action_version',
    coalesce((select version from recsys.post_action_versions where user_id=auth.uid()and post_id=p.id),0),
    'liked',exists(select 1 from feed.post_likes where user_id=auth.uid()and post_id=p.id),
    'less_similar',exists(select 1 from recsys.semantic_suppressions where user_id=auth.uid()and post_id=p.id));
end $$;

create function private.record_post_like_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare viewer uuid:=case when tg_op='INSERT' then new.user_id else old.user_id end;
  target uuid:=case when tg_op='INSERT' then new.post_id else old.post_id end; version bigint;
begin
  -- FK cascades must not recreate deleted parents or manufacture feedback.
  if not exists(select 1 from feed.posts where id=target) then return null; end if;
  if not exists(select 1 from public.profiles where id=viewer)then
    update recsys.post_statistics set likes=greatest(0,likes-1)where post_id=target;
    return null;
  end if;
  perform private.lock_recommendation_user(viewer);
  update recsys.user_states set revision=revision+1 where user_id=viewer returning revision into version;
  insert into recsys.post_statistics as st(post_id,likes)values(target,case when tg_op='INSERT' then 1 else 0 end)
    on conflict(post_id) do update set likes=greatest(0,st.likes+case when tg_op='INSERT' then 1 else -1 end);
  perform private.queue_recommendation_refresh(viewer,version);
  return null;
end $$;
create trigger feed_post_like_feedback after insert or delete on feed.post_likes
  for each row execute function private.record_post_like_change();

create function private.replay_recommendation_action(viewer uuid, request_id uuid, body jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous recsys.action_requests%rowtype;
begin
  if request_id is null then raise exception using errcode='22023',message='request_id_required'; end if;
  select * into previous from recsys.action_requests where user_id=viewer and id=request_id;
  if not found then return null; end if;
  if previous.payload<>body then raise exception using errcode='23505',message='request_id_conflict'; end if;
  return previous.response||jsonb_build_object('replayed',true);
end $$;

create function private.apply_feed_action_impl(requested_id uuid, requested_delivery uuid, requested_action text, expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; d recsys.deliveries%rowtype; p feed.posts%rowtype;
  body jsonb:=jsonb_build_array('post',requested_delivery,requested_action,expected_version); response jsonb; changed integer:=0; action_version bigint;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('feed_action');
  if expected_version is null or expected_version<0 or requested_action is null or requested_action not in ('like','unlike','less_similar','undo_less_similar') then
    raise exception using errcode='22023',message='invalid_feed_action';
  end if;
  s:=private.lock_recommendation_user(auth.uid());
  response:=private.replay_recommendation_action(auth.uid(),requested_id,body);
  if response is not null then return response; end if;
  select * into d from recsys.deliveries where id=requested_delivery and user_id=auth.uid() and valid_until>statement_timestamp();
  if not found or d.epoch<>s.epoch then raise exception using errcode='22023',message='delivery_expired_or_invalidated'; end if;
  select * into p from feed.posts where id=d.post_id and version=d.post_version
    and deleted_at is null and moderation_status='allowed' and private.feed_post_visible(auth.uid(),author_id,audience) for share;
  if not found then raise exception using errcode='22023',message='delivery_expired_or_invalidated'; end if;
  select coalesce((select version from recsys.post_action_versions where user_id=auth.uid()and post_id=p.id),0)into action_version;
  if expected_version<>action_version then raise exception using errcode='PT409',message='feed_action_version_conflict';end if;
  -- Even a no-op intent advances this post's action version. Otherwise an old
  -- first delivery of 'like' could arrive after a newer 'unlike' and undo it.
  insert into recsys.post_action_versions as v(user_id,post_id,version)values(auth.uid(),p.id,1)
    on conflict(user_id,post_id)do update set version=v.version+1 returning version into action_version;
  case requested_action
    when 'like' then
      insert into feed.post_likes(user_id,post_id,post_version,epoch)values(auth.uid(),p.id,p.version,s.epoch)on conflict do nothing;
    when 'unlike' then delete from feed.post_likes where user_id=auth.uid() and post_id=p.id;
    when 'less_similar' then
      insert into recsys.semantic_suppressions as h(user_id,post_id,post_version,epoch)values(auth.uid(),p.id,p.version,s.epoch)
      on conflict(user_id,post_id) do update set post_version=excluded.post_version,epoch=excluded.epoch,created_at=statement_timestamp()
        where h.post_version<>excluded.post_version or h.epoch<>excluded.epoch;
    when 'undo_less_similar' then delete from recsys.semantic_suppressions where user_id=auth.uid() and post_id=p.id;
  end case;
  get diagnostics changed=row_count;
  if changed>0 and requested_action in ('less_similar','undo_less_similar') then
    update recsys.user_states set revision=revision+1 where user_id=auth.uid() returning * into s;
    perform private.queue_recommendation_refresh(auth.uid(),s.revision);
  end if;
  select * into s from recsys.user_states where user_id=auth.uid();
  response:=jsonb_build_object('request_id',requested_id,'changed',changed>0,'replayed',false,'revision',s.revision,
    'action_version',action_version,
    'liked',exists(select 1 from feed.post_likes where user_id=auth.uid() and post_id=p.id),
    'less_similar',exists(select 1 from recsys.semantic_suppressions where user_id=auth.uid() and post_id=p.id));
  insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,body,response);
  return response;
end $$;

create function private.set_recommendation_author_hidden_impl(requested_id uuid, requested_author uuid, requested_hidden boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; body jsonb:=jsonb_build_array('hide_author',requested_author,requested_hidden);
  response jsonb; changed integer;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('feed_preferences');
  if requested_author is null or requested_author=auth.uid() or requested_hidden is null
    or not exists(select 1 from public.profiles where id=requested_author) then
    raise exception using errcode='22023',message='invalid_author';
  end if;
  s:=private.lock_recommendation_user(auth.uid());
  response:=private.replay_recommendation_action(auth.uid(),requested_id,body);
  if response is not null then return response; end if;
  if requested_hidden then
    insert into recsys.hidden_authors(user_id,author_id)values(auth.uid(),requested_author)on conflict do nothing;
  else delete from recsys.hidden_authors where user_id=auth.uid() and author_id=requested_author;
  end if;
  get diagnostics changed=row_count;
  if changed>0 then
    update recsys.user_states set revision=revision+1 where user_id=auth.uid() returning * into s;
    perform private.queue_recommendation_refresh(auth.uid(),s.revision);
  end if;
  response:=jsonb_build_object('request_id',requested_id,'changed',changed>0,'revision',s.revision,'hidden',requested_hidden,'replayed',false);
  insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,body,response);
  return response;
end $$;

create function private.reset_recommendation_interests_impl(requested_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; body jsonb:='["reset"]'::jsonb; response jsonb;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('feed_preferences');
  s:=private.lock_recommendation_user(auth.uid());
  response:=private.replay_recommendation_action(auth.uid(),requested_id,body);
  if response is not null then return response; end if;
  update recsys.user_states set epoch=epoch+1,revision=revision+1,processed_revision=0,profile_complete=false,
    reset_at=statement_timestamp(),current_snapshot=null,prepared_at=null where user_id=auth.uid() returning * into s;
  delete from recsys.interest_clusters where user_id=auth.uid();
  delete from recsys.semantic_suppressions where user_id=auth.uid();
  -- Visible likes and explicit hidden authors survive; old epochs cannot train
  -- the new profile or accept delayed telemetry from a previous session.
  perform private.queue_recommendation_refresh(auth.uid(),s.revision,true);
  response:=jsonb_build_object('request_id',requested_id,'epoch',s.epoch,'revision',s.revision,'replayed',false);
  insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,body,response);
  return response;
end $$;

create function private.record_feed_events_impl(requested_events jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; d recsys.deliveries%rowtype; p feed.posts%rowtype;
  event jsonb; event_id uuid; receipt uuid; kind text; previous jsonb; visible integer; fraction double precision; active integer;
  accepted integer:=0; duplicates integer:=0; stale integer:=0; first_view boolean; elapsed_ms bigint;
  today date:=(statement_timestamp() at time zone 'UTC')::date;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('feed_events');
  if requested_events is null or jsonb_typeof(requested_events)<>'array' or jsonb_array_length(requested_events) not between 1 and 100
    or octet_length(requested_events::text)>65536 then raise exception using errcode='22023',message='invalid_event_batch'; end if;
  s:=private.lock_recommendation_user(auth.uid());
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
      or not private.feed_post_visible(auth.uid(),p.author_id,p.audience) then stale:=stale+1; continue; end if;
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

create function recsys.claim_refresh_job(requested_lease uuid)
returns table(user_id uuid,lease uuid)language plpgsql security definer set search_path='' as $$
begin
  if requested_lease is null then raise exception using errcode='22023',message='invalid_claim'; end if;
  return query with next_job as (
    select j.user_id from recsys.refresh_jobs j where j.available_at<=statement_timestamp() and j.attempts<8
      and (j.locked_until is null or j.locked_until<=statement_timestamp())
    order by j.available_at,j.user_id for update skip locked limit 1
  ) update recsys.refresh_jobs j set lease=requested_lease,locked_until=statement_timestamp()+interval '60 seconds',attempts=j.attempts+1
    from next_job n where j.user_id=n.user_id returning j.user_id,j.lease;
end $$;

create function private.require_refresh_lease(viewer uuid, requested_lease uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from recsys.refresh_jobs where user_id=viewer and lease=requested_lease and locked_until>clock_timestamp()) then
    raise exception using errcode='55000',message='refresh_lease_lost';
  end if;
end $$;

create index feed_post_likes_recent_idx on feed.post_likes(user_id,created_at desc,post_id);
create index recsys_semantic_suppressions_recent_idx on recsys.semantic_suppressions(user_id,created_at desc,post_id);

create function recsys.load_refresh_profile(viewer uuid, requested_lease uuid, requested_model text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_refresh_lease(viewer,requested_lease);
  with s as materialized(select * from recsys.user_states where user_id=viewer), raw as (
    (select l.post_id,l.post_version,2.0::float8 weight,l.created_at at from feed.post_likes l,s
      where l.user_id=viewer and l.epoch=s.epoch and l.created_at>statement_timestamp()-interval '30 days'
      order by l.created_at desc,l.post_id limit 300)
    union all
    (select e.post_id,e.post_version,greatest(least(2,e.active_ms/30000.0),case when e.opened then .2 else 0 end)::float8,e.engaged_at
      from recsys.daily_exposures e,s where e.user_id=viewer and e.epoch=s.epoch
        and e.engaged_at>statement_timestamp()-interval '30 days' and (e.active_ms>0 or e.opened)
      order by e.last_seen_at desc,e.post_id limit 300)
    union all
    (select h.post_id,h.post_version,-3.0::float8,h.created_at from recsys.semantic_suppressions h,s where h.user_id=viewer and h.epoch=s.epoch
      order by h.created_at desc,h.post_id limit 300)
  ), grouped as (
    select post_id,post_version,case when min(weight)<0 then -3 else least(5,sum(weight)) end weight,max(at)at
      from raw group by post_id,post_version order by max(at)desc,post_id limit 300
  ), eligible as materialized(
    select g.* from grouped g join feed.posts p on p.id=g.post_id and p.version=g.post_version
    where p.author_id<>viewer and p.deleted_at is null and p.moderation_status='allowed'
      and private.feed_post_visible(viewer,p.author_id,p.audience)
  ), evidence as (
    select e.post_id,e.post_version,e.weight,e.at,em.embedding::text vector from eligible e
      join recsys.post_embeddings em on em.post_id=e.post_id and em.post_version=e.post_version and em.model=requested_model
  ) select jsonb_build_object('epoch',s.epoch,'revision',s.revision,'at',statement_timestamp(),
    'evidence',coalesce((select jsonb_agg(to_jsonb(e)order by e.at desc,e.post_id)from evidence e),'[]'::jsonb),
    'needs_embeddings',exists(select 1 from eligible e join recsys.index_jobs j on j.post_id=e.post_id and j.post_version=e.post_version
      and j.model=requested_model and j.done_at is null and j.attempts<8
      where not exists(select 1 from recsys.post_embeddings em where em.post_id=e.post_id and em.post_version=e.post_version and em.model=requested_model)))
    into result from s;
  return result;
end $$;

create function recsys.load_refresh_candidates(viewer uuid, requested_lease uuid, requested_epoch integer,
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
      exists(select 1 from social where author_id=p.author_id) social,coalesce(st.impressions,0)impressions,
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

create function recsys.publish_recommendations(viewer uuid, requested_lease uuid, requested_result jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare s recsys.user_states%rowtype; j recsys.refresh_jobs%rowtype; snapshot uuid:=extensions.gen_random_uuid();
  input_epoch integer:=(requested_result->>'epoch')::integer; input_revision bigint:=(requested_result->>'revision')::bigint;
  input_at timestamptz:=(requested_result->>'at')::timestamptz; model_name text:='intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query';
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
    or requested_result->>'feature_version' is distinct from 'personalized-v1'
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
      or not private.feed_post_visible(viewer,p.author_id,p.audience)) then
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
    and old.epoch=input_epoch and old.model='personalized-v1' and old.expires_at>statement_timestamp()+interval '1 minute'
    and s.processed_revision=input_revision and s.profile_complete and not coalesce((requested_result->>'needs_embeddings')::boolean,false)
    and coalesce((select jsonb_agg(jsonb_build_object('post_id',i.post_id,'post_version',i.post_version,'reasons',i.reasons,'sources',i.sources)order by i.position)
      from recsys.feed_snapshot_items i where i.snapshot_id=old.id),'[]')=
      (select coalesce(jsonb_agg(item-'features'-'score'),'[]')from jsonb_array_elements(requested_result->'items')item);
  if not found then
    snapshot:=extensions.gen_random_uuid();
    insert into recsys.feed_snapshots(id,user_id,epoch,revision,model,embedding_model,features_at)
      values(snapshot,viewer,input_epoch,input_revision,'personalized-v1',model_name,input_at);
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
      available_at=statement_timestamp()+case when j.target_revision>input_revision then interval '1 second' else interval '3 seconds' end where user_id=viewer;
  else delete from recsys.refresh_jobs where user_id=viewer; end if;
  return true;
end $$;

create function recsys.retry_refresh_job(viewer uuid, requested_lease uuid)
returns void language sql security definer set search_path='' as $$
  update recsys.refresh_jobs set available_at=statement_timestamp()+make_interval(secs=>least(300,power(2,attempts)::integer)),
    lease=null,locked_until=null,last_error='processing_failed'
  where user_id=viewer and lease=requested_lease and locked_until>statement_timestamp();
$$;

create function recsys.personalization_contract()
returns jsonb language sql immutable set search_path='' as $$
  select jsonb_build_object('version',1,'feature_version','personalized-v1','max_candidates',1200,'max_items',200);
$$;

create function private.create_recommendation_fallback(s recsys.user_states)
returns uuid language plpgsql security definer set search_path='' as $$
declare snapshot uuid:=extensions.gen_random_uuid();
begin
  insert into recsys.feed_snapshots(id,user_id,epoch,revision,model,embedding_model)
    values(snapshot,s.user_id,s.epoch,s.revision,'fallback-v1',
      'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query');
  insert into recsys.feed_snapshot_items(snapshot_id,position,post_id,post_version,reasons,sources)
    select snapshot,(row_number()over(order by p.created_at desc,p.id)-1)::integer,p.id,p.version,array['recent'],array['fresh']
    from (select * from feed.posts where created_at>statement_timestamp()-interval '7 days' and author_id<>s.user_id
      and deleted_at is null and moderation_status='allowed' order by created_at desc,id limit 500)p
    where private.recommendation_post_allowed(s.user_id,p::feed.posts)
    order by p.created_at desc,p.id limit 200;
  update recsys.user_states set current_snapshot=snapshot where user_id=s.user_id;
  return snapshot;
end $$;

create function private.get_for_you_feed_impl(requested_session uuid, after_position integer, requested_limit integer)
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
  return jsonb_build_object('session_id',snapshot.id,'items',items,'expires_at',snapshot.expires_at,'model',snapshot.model,
    'contract_version',1,'has_more',has_more,
    'next_cursor',case when has_more then jsonb_build_object('session_id',snapshot.id,'after_position',next_position)else null end,
    'refresh',jsonb_build_object('status',coalesce(refresh_status,'fresh'),'revision',s.revision,'processed_revision',s.processed_revision,
      'prepared_at',s.prepared_at));
end $$;

create function private.get_recommendation_hidden_authors_impl(after_author uuid, requested_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare items uuid[]; more boolean;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('feed_preferences');
  if requested_limit is null or requested_limit not between 1 and 100 then
    raise exception using errcode='22023',message='invalid_page_size'; end if;
  select array_agg(author_id order by author_id)into items from(select author_id from recsys.hidden_authors
    where user_id=auth.uid() and (after_author is null or author_id>after_author)order by author_id limit requested_limit+1)a;
  more:=coalesce(cardinality(items),0)>requested_limit;
  items:=coalesce(items[1:requested_limit],'{}'::uuid[]);
  return jsonb_build_object('author_ids',items,'next_cursor',case when more then items[cardinality(items)]else null end);
end $$;

create function recsys.retry_failed_recommendation_jobs()
returns integer language plpgsql security definer set search_path='' as $$
declare recovered integer; affected integer;
begin
  update recsys.index_jobs set attempts=0,available_at=statement_timestamp(),last_error=null,lease=null,locked_until=null
    where id in(select id from recsys.index_jobs where done_at is null and attempts>=8
      and(locked_until is null or locked_until<statement_timestamp())order by available_at,id for update skip locked limit 1000);
  get diagnostics recovered=row_count;
  update recsys.refresh_jobs set attempts=0,available_at=statement_timestamp(),last_error=null,lease=null,locked_until=null
    where user_id in(select user_id from recsys.refresh_jobs where attempts>=8
      and(locked_until is null or locked_until<statement_timestamp())order by available_at,user_id for update skip locked limit 1000);
  get diagnostics affected=row_count;
  return recovered+affected;
end $$;

create function recsys.cleanup_recommendations()
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer:=0; affected integer;
begin
  delete from recsys.feed_snapshots where id in(select id from recsys.feed_snapshots
    where expires_at<statement_timestamp()-interval '1 hour'order by expires_at,id for update skip locked limit 25);
  get diagnostics affected=row_count;removed:=removed+affected;
  delete from recsys.deliveries where id in(select id from recsys.deliveries
    where delivered_at<statement_timestamp()-interval '30 days'order by delivered_at,id for update skip locked limit 100);
  get diagnostics affected=row_count;removed:=removed+affected;
  delete from recsys.action_requests where(user_id,id)in(select user_id,id from recsys.action_requests
    where created_at<statement_timestamp()-interval '30 days'order by created_at,user_id,id for update skip locked limit 1000);
  get diagnostics affected=row_count;removed:=removed+affected;
  delete from recsys.daily_exposures where(user_id,post_id,day_utc)in(select user_id,post_id,day_utc from recsys.daily_exposures
    where day_utc<(statement_timestamp()at time zone 'UTC')::date-30 order by day_utc,user_id,post_id for update skip locked limit 1000);
  get diagnostics affected=row_count;removed:=removed+affected;
  -- Acquire user -> job locks like all foreground paths. Never wait behind a
  -- currently active user just to remove an obsolete refresh request.
  with inactive as(select s.user_id from recsys.user_states s where s.active_until<statement_timestamp()
    and exists(select 1 from recsys.refresh_jobs j where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp()))
    order by s.active_until,s.user_id for update skip locked limit 100)
  delete from recsys.refresh_jobs j using inactive s where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp());
  get diagnostics affected=row_count;return removed+affected;
end $$;

create function public.get_for_you_feed(requested_session uuid default null, after_position integer default -1, requested_limit integer default 20)
returns jsonb language sql security invoker set search_path='' as $$
  select private.get_for_you_feed_impl(requested_session,after_position,requested_limit);
$$;
create function public.record_feed_events(requested_events jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.record_feed_events_impl(requested_events);$$;
create function public.apply_feed_action(requested_id uuid, requested_delivery uuid, requested_action text, expected_version bigint)
returns jsonb language sql security invoker set search_path='' as $$select private.apply_feed_action_impl(requested_id,requested_delivery,requested_action,expected_version);$$;
create function public.set_recommendation_author_hidden(requested_id uuid, requested_author uuid, requested_hidden boolean)
returns jsonb language sql security invoker set search_path='' as $$select private.set_recommendation_author_hidden_impl(requested_id,requested_author,requested_hidden);$$;
create function public.reset_recommendation_interests(requested_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.reset_recommendation_interests_impl(requested_id);$$;
create function public.get_recommendation_hidden_authors(after_author uuid default null, requested_limit integer default 30)
returns jsonb language sql security invoker set search_path='' as $$select private.get_recommendation_hidden_authors_impl(after_author,requested_limit);$$;

revoke all on function private.lock_recommendation_user(uuid),private.queue_recommendation_refresh(uuid,bigint,boolean),
  private.recommendation_post_allowed(uuid,feed.posts),private.record_post_like_change(),
  private.replay_recommendation_action(uuid,uuid,jsonb),private.require_refresh_lease(uuid,uuid),
  private.create_recommendation_fallback(recsys.user_states) from public,anon,authenticated,yap_recommendation_worker;

do $$ declare signature text; impl text; begin
  foreach signature in array array[
    'get_for_you_feed(uuid,integer,integer)', 'record_feed_events(jsonb)', 'apply_feed_action(uuid,uuid,text,bigint)',
    'set_recommendation_author_hidden(uuid,uuid,boolean)','reset_recommendation_interests(uuid)',
    'get_recommendation_hidden_authors(uuid,integer)'
  ]loop
    impl:=replace(signature,'(', '_impl(');
    execute 'revoke all on function public.'||signature||',private.'||impl||' from public,anon,authenticated,yap_recommendation_worker';
    execute 'grant execute on function public.'||signature||',private.'||impl||' to authenticated';
  end loop;
end $$;
revoke all on all functions in schema recsys from public,anon,authenticated,yap_recommendation_worker;
grant execute on function
  recsys.claim_index_job(uuid,text),recsys.complete_index_job(bigint,uuid,extensions.vector),
  recsys.retry_index_job(bigint,uuid),recsys.cleanup_index_jobs(),recsys.pipeline_contract(),
  recsys.claim_refresh_job(uuid),recsys.load_refresh_profile(uuid,uuid,text),
  recsys.load_refresh_candidates(uuid,uuid,integer,text,jsonb),recsys.publish_recommendations(uuid,uuid,jsonb),
  recsys.retry_refresh_job(uuid,uuid),recsys.personalization_contract(),
  recsys.retry_failed_recommendation_jobs(),recsys.cleanup_recommendations()
  to yap_recommendation_worker;
notify pgrst,'reload schema';
