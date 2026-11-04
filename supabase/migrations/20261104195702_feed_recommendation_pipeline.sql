-- Canonical feed migration: use the application's actual Supabase database.
-- Text publication/indexing is the first slice. Media, interactions and feed
-- snapshots are added in subsequent migrations, never by the worker at startup.
create extension if not exists vector with schema extensions;

create schema feed;
create schema recsys;
revoke all on schema feed, recsys from public, anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'yap_recommendation_worker') then
    create role yap_recommendation_worker nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  elsif exists (select 1 from pg_catalog.pg_roles where rolname = 'yap_recommendation_worker'
    and (rolsuper or rolcreatedb or rolcreaterole or rolbypassrls or rolcanlogin)) then
    raise exception 'Existing yap_recommendation_worker must be a restricted NOLOGIN role';
  end if;
end $$;

create table feed.posts (
  id uuid primary key,
  author_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (char_length(text) between 1 and 1000 and text ~ '[^[:space:]]'),
  audience text not null check (audience in ('public', 'friends')),
  language text not null check (language in ('ru', 'en')),
  version integer not null default 1 check (version > 0),
  -- Retain the original request so a retry after an edit stays idempotent.
  creation_request jsonb not null,
  moderation_status text not null default 'allowed' check (moderation_status in ('allowed', 'hidden')),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deleted_at timestamptz
);
create index feed_posts_recent_idx on feed.posts (created_at desc, id)
  where deleted_at is null and moderation_status = 'allowed';
create index feed_posts_author_idx on feed.posts (author_id, created_at desc, id);

create table private.feed_operation_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation text not null check (operation in ('post_create', 'post_edit', 'post_delete', 'post_read',
    'post_create_request', 'post_edit_request', 'post_delete_request')),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0),
  day_utc date not null,
  day_count integer not null check (day_count > 0),
  primary key (user_id, operation)
);

create table recsys.index_jobs (
  id bigint generated always as identity primary key,
  post_id uuid not null references feed.posts(id) on delete cascade,
  post_version integer not null,
  model text not null,
  available_at timestamptz not null default statement_timestamp(),
  attempts integer not null default 0 check (attempts between 0 and 8),
  lease uuid,
  locked_until timestamptz,
  done_at timestamptz,
  last_error text check (last_error = 'processing_failed'),
  created_at timestamptz not null default statement_timestamp(),
  unique (post_id, post_version, model),
  check ((lease is null) = (locked_until is null))
);
create index recsys_index_jobs_ready_idx on recsys.index_jobs (model, available_at, id)
  where done_at is null and attempts < 8;
create index recsys_index_jobs_cleanup_idx on recsys.index_jobs (done_at, id) where done_at is not null;

create table recsys.post_embeddings (
  post_id uuid primary key references feed.posts(id) on delete cascade,
  post_version integer not null,
  model text not null,
  embedding extensions.vector(384) not null,
  updated_at timestamptz not null default statement_timestamp(),
  check (extensions.vector_norm(embedding) between 0.999 and 1.001)
);
create index recsys_post_embeddings_search_idx on recsys.post_embeddings
  using hnsw (embedding extensions.vector_cosine_ops);

alter table feed.posts enable row level security;
alter table private.feed_operation_limits enable row level security;
alter table recsys.index_jobs enable row level security;
alter table recsys.post_embeddings enable row level security;
-- No raw table access. Clients use checked RPCs; the worker uses narrow functions.
revoke all on all tables in schema feed, recsys from public, anon, authenticated, yap_recommendation_worker;
revoke all on all sequences in schema recsys from public, anon, authenticated, yap_recommendation_worker;
revoke all on table private.feed_operation_limits from public, anon, authenticated, yap_recommendation_worker;

create function private.consume_feed_quota(requested_operation text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  minute_limit integer;
  daily_limit integer;
  accepted integer;
  today date := (statement_timestamp() at time zone 'UTC')::date;
begin
  if viewer is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  case requested_operation
    when 'post_create' then minute_limit := 6; daily_limit := 100;
    when 'post_edit' then minute_limit := 6; daily_limit := 100;
    when 'post_delete' then minute_limit := 6; daily_limit := 100;
    when 'post_read' then minute_limit := 60; daily_limit := 86400;
    when 'post_create_request' then minute_limit := 60; daily_limit := 86400;
    when 'post_edit_request' then minute_limit := 60; daily_limit := 86400;
    when 'post_delete_request' then minute_limit := 60; daily_limit := 86400;
    else raise exception using errcode = '22023', message = 'invalid_feed_operation';
  end case;
  insert into private.feed_operation_limits as limits
    (user_id, operation, window_started_at, request_count, day_utc, day_count)
  values (viewer, requested_operation, statement_timestamp(), 1, today, 1)
  on conflict (user_id, operation) do update set
    window_started_at = case when limits.window_started_at <= statement_timestamp() - interval '1 minute'
      then statement_timestamp() else limits.window_started_at end,
    request_count = case when limits.window_started_at <= statement_timestamp() - interval '1 minute'
      then 1 else limits.request_count + 1 end,
    day_utc = today,
    day_count = case when limits.day_utc < today then 1 else limits.day_count + 1 end
  where (limits.window_started_at <= statement_timestamp() - interval '1 minute' or limits.request_count < minute_limit)
    and (limits.day_utc < today or limits.day_count < daily_limit)
  returning request_count into accepted;
  if accepted is null then
    raise exception using errcode = '42901', message = 'feed_rate_limited';
  end if;
end $$;

-- This predicate is private: callers cannot use it to probe other users' access.
create function private.feed_post_visible(viewer uuid, target_author uuid, target_audience text)
returns boolean language sql stable security definer set search_path = '' as $$
  select viewer is not null
    and not private.is_account_globally_banned(target_author)
    and not private.is_account_pending_deletion(target_author)
    and not private.is_user_pair_blocked_impl(viewer, target_author)
    and (viewer = target_author or target_audience = 'public' or exists (
      select 1 from public.friendships f
      where f.user_one_id = least(viewer, target_author)
        and f.user_two_id = greatest(viewer, target_author)
    ));
$$;

create function private.feed_post_json(p feed.posts)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'author_id', p.author_id, 'text', p.text,
    'audience', p.audience, 'language', p.language, 'version', p.version,
    'created_at', p.created_at, 'updated_at', p.updated_at);
$$;

create function private.create_feed_post_impl(requested_id uuid, requested_text text,
  requested_audience text, requested_language text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  p feed.posts%rowtype;
  fingerprint jsonb := jsonb_build_array(requested_text, requested_audience, requested_language);
begin
  perform private.require_active_account();
  if requested_id is null or requested_text is null or char_length(requested_text) not between 1 and 1000
    or requested_text !~ '[^[:space:]]' or requested_audience is null or requested_audience not in ('public', 'friends')
    or requested_language is null or requested_language not in ('ru', 'en') then
    raise exception using errcode = '22023', message = 'invalid_post';
  end if;
  -- A separate request budget bounds successful idempotent retries without
  -- charging the mutation budget twice. It also precedes per-post locking.
  perform private.consume_feed_quota('post_create_request');
  -- Serialize identical request ids before charging the quota. Concurrent
  -- retries produce exactly one post, one quota charge and one outbox job.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('feed-create:' || requested_id::text, 0));
  select * into p from feed.posts where id = requested_id;
  if found then
    if p.author_id <> viewer or p.creation_request <> fingerprint or p.deleted_at is not null then
      raise exception using errcode = '23505', message = 'post_id_conflict';
    end if;
    return private.feed_post_json(p);
  end if;
  perform private.consume_feed_quota('post_create');
  insert into feed.posts (id, author_id, text, audience, language, creation_request)
    values (requested_id, viewer, requested_text, requested_audience, requested_language, fingerprint)
    returning * into p;
  return private.feed_post_json(p);
end $$;

create function private.edit_feed_post_impl(requested_id uuid, expected_version integer, requested_text text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p feed.posts%rowtype;
begin
  perform private.require_active_account();
  if requested_text is null or char_length(requested_text) not between 1 and 1000 or requested_text !~ '[^[:space:]]'
    or expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'invalid_post';
  end if;
  perform private.consume_feed_quota('post_edit_request');
  select * into p from feed.posts where id = requested_id and author_id = auth.uid()
    and deleted_at is null and moderation_status = 'allowed' for update;
  if not found then raise exception using errcode = 'P0002', message = 'post_not_found'; end if;
  if p.version <> expected_version then
    raise exception using errcode = '40001', message = 'post_version_conflict';
  end if;
  if p.text = requested_text then return private.feed_post_json(p); end if;
  perform private.consume_feed_quota('post_edit');
  update feed.posts set text = requested_text where id = p.id returning * into p;
  return private.feed_post_json(p);
end $$;

create function private.delete_feed_post_impl(requested_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare p feed.posts%rowtype;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('post_delete_request');
  select * into p from feed.posts where id = requested_id and author_id = auth.uid() for update;
  if not found then raise exception using errcode = 'P0002', message = 'post_not_found'; end if;
  if p.deleted_at is not null then return; end if;
  perform private.consume_feed_quota('post_delete');
  update feed.posts set deleted_at = statement_timestamp() where id = p.id;
end $$;

create function private.get_feed_post_impl(requested_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('post_read');
  select private.feed_post_json(p) into result from feed.posts p where p.id = requested_id
    and p.deleted_at is null and p.moderation_status = 'allowed'
    and private.feed_post_visible(auth.uid(), p.author_id, p.audience);
  return result;
end $$;

create function private.version_feed_post()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.version := old.version + case when new.text is distinct from old.text then 1 else 0 end;
  new.updated_at := statement_timestamp();
  return new;
end $$;
create trigger feed_post_version before update on feed.posts
  for each row execute function private.version_feed_post();

create function private.queue_feed_post_index()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.text is not distinct from old.text
    and new.moderation_status is not distinct from old.moderation_status
    and new.deleted_at is not distinct from old.deleted_at then return null; end if;
  -- Invalidating the derived vector and recording the next job is part of the
  -- publication transaction, so neither can be lost on a worker/network outage.
  delete from recsys.post_embeddings where post_id = new.id;
  if new.deleted_at is null and new.moderation_status = 'allowed' then
    insert into recsys.index_jobs (post_id, post_version, model)
    values (new.id, new.version, 'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')
    on conflict (post_id, post_version, model) do update set
      done_at = null, attempts = 0, available_at = statement_timestamp(), lease = null, locked_until = null, last_error = null;
  end if;
  return null;
end $$;
create trigger feed_post_index_outbox after insert or update of text, moderation_status, deleted_at on feed.posts
  for each row execute function private.queue_feed_post_index();

create function public.create_feed_post(requested_id uuid, requested_text text,
  requested_audience text default 'public', requested_language text default 'ru')
returns jsonb language sql security invoker set search_path = '' as $$
  select private.create_feed_post_impl(requested_id, requested_text, requested_audience, requested_language);
$$;
create function public.edit_feed_post(requested_id uuid, expected_version integer, requested_text text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.edit_feed_post_impl(requested_id, expected_version, requested_text);
$$;
create function public.delete_feed_post(requested_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.delete_feed_post_impl(requested_id);
$$;
create function public.get_feed_post(requested_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.get_feed_post_impl(requested_id);
$$;

-- A worker receives only content needed for its claimed job; it cannot scan
-- profiles/private tables, mutate content or issue client-facing RPCs.
create function recsys.claim_index_job(requested_lease uuid, requested_model text)
returns table (id bigint, lease uuid, post_id uuid, post_version integer, text text)
language plpgsql security definer set search_path = '' as $$
begin
  if requested_lease is null or requested_model is null then
    raise exception using errcode = '22023', message = 'invalid_claim';
  end if;
  return query with candidate as (
    select j.id from recsys.index_jobs j where j.model = requested_model
      and j.done_at is null and j.attempts < 8 and j.available_at <= statement_timestamp()
      and (j.locked_until is null or j.locked_until <= statement_timestamp())
    order by j.available_at, j.id for update skip locked limit 1
  ), claimed as (
    update recsys.index_jobs j set lease = requested_lease,
      locked_until = statement_timestamp() + interval '60 seconds', attempts = j.attempts + 1
    from candidate c where j.id = c.id returning j.*
  ) select j.id, j.lease, j.post_id, j.post_version,
    case when p.version = j.post_version and p.deleted_at is null and p.moderation_status = 'allowed'
      and not private.is_account_globally_banned(p.author_id)
      and not private.is_account_pending_deletion(p.author_id) then p.text else '' end
    from claimed j join feed.posts p on p.id = j.post_id;
end $$;

create function recsys.complete_index_job(requested_id bigint, requested_lease uuid, requested_embedding extensions.vector)
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
  if p.id is not null and p.version = j.post_version and p.deleted_at is null and p.moderation_status = 'allowed'
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

create function recsys.retry_index_job(requested_id bigint, requested_lease uuid)
returns void language sql security definer set search_path = '' as $$
  update recsys.index_jobs set available_at = statement_timestamp() +
    make_interval(secs => least(300, power(2, attempts)::integer)),
    lease = null, locked_until = null, last_error = 'processing_failed'
  where id = requested_id and lease = requested_lease and done_at is null and locked_until > statement_timestamp();
$$;

create function recsys.cleanup_index_jobs()
returns void language sql security definer set search_path = '' as $$
  delete from recsys.index_jobs where id in (
    select id from recsys.index_jobs where done_at < statement_timestamp() - interval '7 days'
    order by done_at, id for update skip locked limit 1000
  );
$$;

create function recsys.pipeline_contract()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('version', 1, 'embedding_model',
    'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query');
$$;

revoke all on function private.consume_feed_quota(text), private.feed_post_visible(uuid, uuid, text),
  private.feed_post_json(feed.posts), private.version_feed_post(), private.queue_feed_post_index()
  from public, anon, authenticated, yap_recommendation_worker;
revoke all on function private.create_feed_post_impl(uuid, text, text, text),
  private.edit_feed_post_impl(uuid, integer, text), private.delete_feed_post_impl(uuid), private.get_feed_post_impl(uuid),
  public.create_feed_post(uuid, text, text, text), public.edit_feed_post(uuid, integer, text),
  public.delete_feed_post(uuid), public.get_feed_post(uuid) from public, anon, authenticated, yap_recommendation_worker;
grant execute on function private.create_feed_post_impl(uuid, text, text, text),
  private.edit_feed_post_impl(uuid, integer, text), private.delete_feed_post_impl(uuid), private.get_feed_post_impl(uuid),
  public.create_feed_post(uuid, text, text, text), public.edit_feed_post(uuid, integer, text),
  public.delete_feed_post(uuid), public.get_feed_post(uuid) to authenticated;
revoke all on all functions in schema recsys from public, anon, authenticated;
grant usage on schema recsys, extensions to yap_recommendation_worker;
grant execute on function recsys.claim_index_job(uuid, text), recsys.complete_index_job(bigint, uuid, extensions.vector),
  recsys.retry_index_job(bigint, uuid), recsys.cleanup_index_jobs(), recsys.pipeline_contract() to yap_recommendation_worker;

notify pgrst, 'reload schema';
