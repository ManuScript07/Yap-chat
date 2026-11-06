-- Server-verified transitions, not a client event endpoint or training labels.
-- No retrospective backfill: mutable current state cannot reconstruct history.
create table recsys.feedback_history_contract (
    singleton boolean primary key default true check (singleton),
    version smallint not null default 1 check (version = 1),
    started_at timestamptz not null default clock_timestamp(),
    retention_days integer not null default 30 check (retention_days = 30)
);
insert into recsys.feedback_history_contract default values;

create table recsys.feedback_facts (
    sequence bigint generated always as identity primary key,
    event_id uuid not null default extensions.gen_random_uuid(),
    contract_version smallint not null default 1 check (contract_version = 1),
    user_id uuid not null references public.profiles(id) on delete cascade,
    epoch integer not null check (epoch > 0),
    recorded_at timestamptz not null default clock_timestamp(),
    transaction_id xid8 not null default pg_current_xact_id(),
    source text not null,
    request_id uuid,
    kind text not null check (kind in ('like','less_similar','follow','hide_author','comment',
        'comment_like','repost','quote','report','reset','content','impression','dwell','open_post')),
    target_type text not null check (target_type in ('post','comment','repost','author','user')),
    target_id uuid not null,
    target_version integer,
    state_version bigint,
    post_id uuid,
    post_version integer,
    author_id uuid,
    original_post_id uuid,
    root_id uuid,
    reply_to_id uuid,
    active boolean,
    own_content boolean not null default false,
    delivery_id uuid,
    surface text not null default 'unattributed' check (surface in ('unattributed','for_you','friends','nearby','direct')),
    active_ms integer check (active_ms between 0 and 120000),
    opened boolean,
    context jsonb not null default '{}' check (jsonb_typeof(context) = 'object'),
    unique (user_id,event_id),
    check ((post_id is null) = (post_version is null)),
    check (target_version is null or target_version > 0),
    check (state_version is null or state_version > 0)
);
-- Facts deliberately have no FK to short-lived deliveries/snapshots or content:
-- their typed versions survive cleanup/deletion; no text, image or report reason.
create index feedback_facts_user_epoch_idx on recsys.feedback_facts(user_id,epoch,sequence);
create index feedback_facts_context_idx on recsys.feedback_facts(user_id,transaction_id,kind,target_id,sequence desc);
create index feedback_facts_post_idx on recsys.feedback_facts(post_id,recorded_at,sequence) where post_id is not null;
create index feedback_facts_retention_idx on recsys.feedback_facts(recorded_at,sequence);
create index feedback_facts_delivery_idx on recsys.feedback_facts(delivery_id,sequence desc) where delivery_id is not null;
alter table recsys.feedback_facts enable row level security;
alter table recsys.feedback_history_contract enable row level security;
revoke all on recsys.feedback_facts,recsys.feedback_history_contract from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on sequence recsys.feedback_facts_sequence_seq from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;

create function private.feed_feedback_delivery_context(receipt recsys.deliveries)
returns jsonb language sql stable security definer set search_path='' as $$
    select jsonb_strip_nulls(jsonb_build_object('snapshot_id',receipt.snapshot_id,'position',receipt.position,
        'model',receipt.model,'embedding_model',receipt.embedding_model,'features',receipt.features,
        'features_at',receipt.features_at,'feature_version',s.feature_version,
        'policy_version',s.policy_version,'embedding_space',s.embedding_space))
    from (select 1) seed left join recsys.feed_snapshots s on s.id=receipt.snapshot_id and s.user_id=receipt.user_id;
$$;

create function private.capture_feed_feedback_fact()
returns trigger language plpgsql security definer set search_path='' as $$
declare
    r jsonb; previous jsonb; actor uuid; target uuid; target_kind text; event_kind text;
    post uuid; post_ver integer; target_ver integer; state_ver bigint; original uuid; root uuid; reply uuid;
    enabled boolean; owner uuid; generation integer; request uuid; own_target boolean:=false;
    d recsys.deliveries%rowtype; c feed.comments%rowtype;
    context jsonb:='{}'; active_time integer; is_opened boolean; receipt uuid; tab text:='unattributed';
    prior_active integer;prior_opened boolean;has_attention boolean;
begin
    r:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
    if tg_op='UPDATE' then previous:=to_jsonb(old); end if;
    case tg_table_name
    when 'post_likes','semantic_suppressions' then
        actor:=(r->>'user_id')::uuid; post:=(r->>'post_id')::uuid; post_ver:=(r->>'post_version')::integer;
        generation:=(r->>'epoch')::integer;target:=post;target_kind:='post';target_ver:=post_ver;
        event_kind:=case when tg_table_name='post_likes' then 'like' else 'less_similar' end;
        enabled:=tg_op<>'DELETE';
        select version into state_ver from recsys.post_action_versions where user_id=actor and post_id=post;
    when 'author_follows' then
        if tg_op='UPDATE' and r->'following'=previous->'following' and r->'version'=previous->'version' then return null;end if;
        actor:=(r->>'follower_id')::uuid;target:=(r->>'author_id')::uuid;target_kind:='author';event_kind:='follow';
        enabled:=tg_op<>'DELETE' and (r->>'following')::boolean;state_ver:=(r->>'version')::bigint;
    when 'hidden_authors' then
        actor:=(r->>'user_id')::uuid;target:=(r->>'author_id')::uuid;target_kind:='author';event_kind:='hide_author';enabled:=tg_op<>'DELETE';
    when 'comments' then
        if tg_op='UPDATE' and r->'version'=previous->'version' and r->'moderation_status'=previous->'moderation_status'
            and r->'deleted_at'=previous->'deleted_at' and r->'author_id'=previous->'author_id' then return null;end if;
        actor:=coalesce((r->>'author_id')::uuid,(previous->>'author_id')::uuid);
        target:=(r->>'id')::uuid;target_kind:='comment';event_kind:='comment';target_ver:=(r->>'version')::integer;
        post:=(r->>'post_id')::uuid;post_ver:=(r->>'post_version')::integer;
        root:=(r->>'root_id')::uuid;reply:=(r->>'reply_to_id')::uuid;
        enabled:=tg_op<>'DELETE' and r->>'deleted_at' is null and r->>'moderation_status'='allowed' and r->>'author_id' is not null;
        if tg_op='INSERT' then request:=target;end if;
    when 'comment_likes' then
        actor:=(r->>'user_id')::uuid;target:=(r->>'comment_id')::uuid;target_kind:='comment';event_kind:='comment_like';
        select * into c from feed.comments where id=target;
        -- A cascading hard deletion has a separate content/comment lifecycle fact.
        if not found then return null;end if;
        target_ver:=(r->>'comment_version')::integer;post:=c.post_id;post_ver:=(r->>'post_version')::integer;
        generation:=(r->>'epoch')::integer;root:=c.root_id;reply:=c.reply_to_id;enabled:=tg_op<>'DELETE';
        own_target:=c.author_id=actor;
        select version into state_ver from feed.comment_action_versions where user_id=actor and comment_id=target;
    when 'reposts' then
        if tg_op='UPDATE' and r->'version'=previous->'version' and r->'deleted_at'=previous->'deleted_at'
            and r->'moderation_status'=previous->'moderation_status' then return null;end if;
        actor:=(r->>'author_id')::uuid;target:=(r->>'id')::uuid;target_kind:='post';target_ver:=(r->>'version')::integer;
        post:=(r->>'original_post_id')::uuid;post_ver:=(r->>'original_version')::integer;original:=post;
        event_kind:=case when r->>'post_id' is null then 'repost' else 'quote' end;
        target_kind:=case when r->>'post_id' is null then 'repost' else 'post' end;
        enabled:=tg_op<>'DELETE' and r->>'deleted_at' is null and r->>'moderation_status'='allowed';
        if tg_op='INSERT' then request:=target;end if;
    when 'user_reports' then
        actor:=(r->>'reporter_user_id')::uuid;target_kind:=r->>'target_type';event_kind:='report';enabled:=true;
        target:=case when target_kind='user' then (r->>'target_user_id')::uuid else (r->>'content_id')::uuid end;
        if target_kind='post' then post:=target;post_ver:=(r->'content_snapshot'->>'version')::integer;target_ver:=post_ver;
        elsif target_kind='comment' then
            post:=(r->'content_snapshot'->>'post_id')::uuid;target_ver:=(r->'content_snapshot'->>'version')::integer;
            root:=(r->'content_snapshot'->>'root_id')::uuid;
            select version into post_ver from feed.posts where id=post;
        end if;
    when 'user_states' then
        if new.epoch=old.epoch then return null;end if;
        actor:=new.user_id;generation:=new.epoch;target:=actor;target_kind:='user';event_kind:='reset';enabled:=true;state_ver:=new.revision;
    when 'posts' then
        if tg_op='UPDATE' and r->'version'=previous->'version' and r->'deleted_at'=previous->'deleted_at'
            and r->'moderation_status'=previous->'moderation_status' then return null;end if;
        actor:=(r->>'author_id')::uuid;target:=(r->>'id')::uuid;post:=target;target_kind:='post';event_kind:='content';
        post_ver:=(r->>'version')::integer;target_ver:=post_ver;original:=(r->>'original_post_id')::uuid;
        enabled:=tg_op<>'DELETE' and r->>'deleted_at' is null and r->>'moderation_status'='allowed';
    when 'telemetry_events' then
        actor:=(r->>'user_id')::uuid;receipt:=(r->>'delivery_id')::uuid;request:=(r->>'id')::uuid;
        select * into d from recsys.deliveries where id=receipt and user_id=actor;
        if not found then raise exception 'feedback delivery missing';end if;
        post:=d.post_id;post_ver:=d.post_version;generation:=d.epoch;target:=post;target_ver:=post_ver;target_kind:='post';
        event_kind:=r->'payload'->>'kind';enabled:=true;active_time:=d.active_ms;is_opened:=d.opened;tab:=d.surface;
        select active_ms,opened into prior_active,prior_opened from recsys.feedback_facts
            where delivery_id=receipt and kind in('impression','dwell','open_post')order by sequence desc limit 1;
        has_attention:=found;
        -- Distinct telemetry UUIDs need not mean new attention. Keep only the
        -- first qualification and actual cumulative progress in this journal.
        -- Raw idempotency receipts remain in telemetry_events as before.
        if(event_kind='impression'and has_attention)
            or(event_kind='dwell'and active_time<=coalesce(prior_active,0))
            or(event_kind='open_post'and coalesce(prior_opened,false))then return null;end if;
        context:=private.feed_feedback_delivery_context(d);
    else raise exception 'unsupported feedback source';
    end case;
    -- Never recreate histories during account cascades. Account removal deletes facts.
    if actor is null or not exists(select 1 from public.profiles where id=actor) then return null;end if;
    if generation is null then select epoch into generation from recsys.user_states where user_id=actor;end if;
    if post is not null then select author_id,coalesce(original,original_post_id) into owner,original from feed.posts where id=post;end if;
    insert into recsys.feedback_facts(user_id,epoch,source,request_id,kind,target_type,target_id,target_version,state_version,
        post_id,post_version,author_id,original_post_id,root_id,reply_to_id,active,own_content,delivery_id,surface,active_ms,opened,context)
    values(actor,coalesce(generation,1),tg_table_schema||'.'||tg_table_name,request,event_kind,target_kind,target,target_ver,state_ver,
        post,post_ver,owner,original,root,reply,enabled,coalesce(owner=actor,false)or coalesce(own_target,false),receipt,tab,active_time,is_opened,context);
    return null;
end $$;

-- Attach request/delivery context after the checked RPC has saved its idempotent
-- response. State mutations and this enrichment commit atomically. No-op intents
-- also record their accepted state/version; retrying an existing request does not.
create function private.attribute_feed_feedback_request()
returns trigger language plpgsql security definer set search_path='' as $$
declare
    operation text:=new.payload->>0;event_kind text;target uuid;target_kind text;enabled boolean;ver bigint;
    generation integer;chosen bigint;post uuid;post_ver integer;target_ver integer;owner uuid;
    receipt uuid;d recsys.deliveries%rowtype;c feed.comments%rowtype;
begin
    select epoch into generation from recsys.user_states where user_id=new.user_id;
    case operation
    when 'post' then
        receipt:=(new.payload->>1)::uuid;select * into d from recsys.deliveries where id=receipt and user_id=new.user_id;
        if not found then raise exception 'feedback action delivery missing';end if;
        event_kind:=case when new.payload->>2 in ('like','unlike')then 'like'else 'less_similar'end;
        enabled:=(new.response->>case when event_kind='like'then 'liked'else 'less_similar'end)::boolean;
        target:=d.post_id;post:=target;post_ver:=d.post_version;target_ver:=post_ver;target_kind:='post';
        generation:=d.epoch;ver:=(new.response->>'action_version')::bigint;
    when 'author_follow' then
        event_kind:='follow';target:=(new.payload->>1)::uuid;target_kind:='author';
        enabled:=(new.response->>'following')::boolean;ver:=(new.response->>'version')::bigint;
    when 'hide_author' then
        event_kind:='hide_author';target:=(new.payload->>1)::uuid;target_kind:='author';enabled:=(new.response->>'hidden')::boolean;
    when 'reset' then event_kind:='reset';target:=new.user_id;target_kind:='user';enabled:=true;
    when 'comment_like' then
        event_kind:='comment_like';target:=(new.payload->>1)::uuid;target_kind:='comment';enabled:=(new.response->>'liked')::boolean;
        ver:=(new.response->>'action_version')::bigint;select * into c from feed.comments where id=target;
        post:=c.post_id;post_ver:=(new.payload->>5)::integer;target_ver:=(new.payload->>4)::integer;
    when 'comment_mutation' then
        event_kind:='comment';target:=(new.payload->>1)::uuid;target_kind:='comment';enabled:=not(new.response->>'deleted')::boolean;
    when 'delete_repost' then
        target:=(new.payload->>1)::uuid;target_kind:='post';enabled:=false;
        select case when post_id is null then 'repost'else 'quote'end into event_kind from feed.reposts where id=target;
    when 'content_report' then
        event_kind:='report';target_kind:=new.payload->>1;target:=(new.payload->>2)::uuid;enabled:=true;
    else return null;
    end case;
    select sequence into chosen from recsys.feedback_facts where user_id=new.user_id and transaction_id=pg_current_xact_id()
        and kind=event_kind and target_id=target and request_id is null order by sequence desc limit 1;
    if chosen is not null then
        update recsys.feedback_facts set request_id=new.id,state_version=coalesce(ver,state_version),epoch=coalesce(generation,epoch),
            post_id=coalesce(post,post_id),post_version=coalesce(post_ver,post_version),target_version=coalesce(target_ver,target_version),
            delivery_id=receipt,surface=case when receipt is null then surface else d.surface end,
            context=case when receipt is null then context else private.feed_feedback_delivery_context(d)end
        where sequence=chosen;
    elsif operation in('post','author_follow','hide_author','comment_like') then
        -- No-op comment edits/deletes already have lifecycle history; no fake
        -- interaction is added. Versioned state intents do establish a checkpoint.
        if post is not null then select author_id into owner from feed.posts where id=post;end if;
        insert into recsys.feedback_facts(user_id,epoch,source,request_id,kind,target_type,target_id,target_version,state_version,
            post_id,post_version,author_id,active,own_content,delivery_id,surface,context,root_id,reply_to_id)
        values(new.user_id,coalesce(generation,1),'recsys.action_requests',new.id,event_kind,target_kind,target,target_ver,ver,
            post,post_ver,owner,enabled,coalesce(owner=new.user_id,false)or coalesce(operation='comment_like'and c.author_id=new.user_id,false),receipt,coalesce(d.surface,'unattributed'),
            case when receipt is null then '{}'::jsonb else private.feed_feedback_delivery_context(d)end,c.root_id,c.reply_to_id);
    end if;
    return null;
end $$;

create trigger feedback_post_likes after insert or delete on feed.post_likes for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_suppressions after insert or update or delete on recsys.semantic_suppressions for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_follows after insert or update or delete on feed.author_follows for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_hidden_authors after insert or delete on recsys.hidden_authors for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_comments after insert or update or delete on feed.comments for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_comment_likes after insert or delete on feed.comment_likes for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_reposts after insert or update or delete on feed.reposts for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_reports after insert on private.user_reports for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_reset after update of epoch on recsys.user_states for each row execute function private.capture_feed_feedback_fact();
-- Version may be changed by a BEFORE trigger even when UPDATE targets only text.
-- Filter OLD/NEW inside the capture function rather than an UPDATE OF column list.
create trigger feedback_content after insert or update or delete on feed.posts for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_telemetry after insert on recsys.telemetry_events for each row execute function private.capture_feed_feedback_fact();
create trigger feedback_requests after insert on recsys.action_requests for each row execute function private.attribute_feed_feedback_request();

revoke all on function private.feed_feedback_delivery_context(recsys.deliveries),private.capture_feed_feedback_fact(),
    private.attribute_feed_feedback_request() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;

-- Existing maintenance runs independently of idle queue time; deletion stays bounded.
create or replace function recsys.cleanup_recommendations()
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
  delete from feed.page_sessions where id in(select id from feed.page_sessions where expires_at<statement_timestamp()
    order by expires_at,id for update skip locked limit 10);
  get diagnostics affected=row_count;removed:=removed+affected;
  delete from recsys.feedback_facts where sequence in(select sequence from recsys.feedback_facts
    where recorded_at<statement_timestamp()-interval '30 days' order by recorded_at,sequence for update skip locked limit 1000);
  get diagnostics affected=row_count;removed:=removed+affected;
  -- Acquire user -> job locks like all foreground paths. Never wait behind a
  -- currently active user just to remove an obsolete refresh request.
  with inactive as(select s.user_id from recsys.user_states s where s.active_until<statement_timestamp()
    and exists(select 1 from recsys.refresh_jobs j where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp()))
    order by s.active_until,s.user_id for update skip locked limit 100)
  delete from recsys.refresh_jobs j using inactive s where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp());
  get diagnostics affected=row_count;return removed+affected;
end $$;

-- Own views remain valid UI telemetry but never inflate public impression counts.
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
        if first_view and p.author_id<>auth.uid() then insert into recsys.post_statistics as st(post_id,impressions)values(p.id,1)
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
