create table recsys.feed_scrolls (
    id uuid primary key default extensions.gen_random_uuid(),
    request_id uuid not null,
    user_id uuid not null references public.profiles(id) on delete cascade,
    epoch integer not null,
    seed_id uuid,
    seed_after integer not null default -1,
    archive_at timestamptz not null,
    archive_id uuid,
    archive_done boolean not null default false,
    next_token uuid,
    next_position integer not null default 0,
    unique_count integer not null default 0,
    expires_at timestamptz not null,
    unique(user_id,request_id)
);
create index feed_scrolls_user_idx on recsys.feed_scrolls(user_id, expires_at, id);
create index feed_scrolls_seed_idx on recsys.feed_scrolls(seed_id, expires_at) where seed_id is not null;
create index feed_scrolls_expiry_idx on recsys.feed_scrolls(expires_at, id);

create table recsys.feed_scroll_pages (
    scroll_id uuid not null references recsys.feed_scrolls(id) on delete cascade,
    token uuid not null,
    page_size integer not null,
    receipts uuid[] not null,
    next_token uuid,
    primary key (scroll_id, token)
);
create table recsys.feed_scroll_seen (
    scroll_id uuid not null references recsys.feed_scrolls(id) on delete cascade,
    post_id uuid not null,
    first_position integer not null,
    primary key (scroll_id, post_id)
);
alter table recsys.feed_scrolls enable row level security;
alter table recsys.feed_scroll_pages enable row level security;
alter table recsys.feed_scroll_seen enable row level security;
revoke all on recsys.feed_scrolls, recsys.feed_scroll_pages, recsys.feed_scroll_seen
    from public, anon, authenticated, service_role, yap_recommendation_worker, yap_feed_media_worker, yap_feed_vision_worker;

alter table recsys.deliveries add column source_snapshot_id uuid;

create or replace function private.stamp_feed_delivery_versions()
returns trigger language plpgsql security definer set search_path='' as $$
begin
    if new.source_snapshot_id is not null or (new.snapshot_id is not null and new.model<>'archive-v2') then
        select s.feature_version,s.policy_version,s.embedding_space
          into strict new.feature_version,new.policy_version,new.embedding_space from recsys.feed_snapshots s
          where s.id=coalesce(new.source_snapshot_id,new.snapshot_id) and s.user_id=new.user_id;
    else
        new.feature_version:='none';
        new.policy_version:=new.model;
        new.embedding_space:=new.embedding_model;
    end if;
    return new;
end $$;

create or replace function private.feed_feedback_delivery_context(receipt recsys.deliveries)
returns jsonb language sql stable security definer set search_path='' as $$
    select jsonb_strip_nulls(jsonb_build_object('snapshot_id',coalesce(receipt.source_snapshot_id,receipt.snapshot_id),'position',receipt.position,
        'model',receipt.model,'embedding_model',receipt.embedding_model,'features',receipt.features,
        'features_at',receipt.features_at,
        'feature_version',case when receipt.source_snapshot_id is not null or receipt.model='archive-v2'
            then receipt.feature_version else s.feature_version end,
        'policy_version',case when receipt.source_snapshot_id is not null or receipt.model='archive-v2'
            then receipt.policy_version else s.policy_version end,
        'embedding_space',case when receipt.source_snapshot_id is not null or receipt.model='archive-v2'
            then receipt.embedding_space else s.embedding_space end))
    from (select 1) legacy left join recsys.feed_snapshots s on s.id=receipt.snapshot_id and s.user_id=receipt.user_id;
$$;

-- Split the seek into two indexed ranges to match created_at DESC, id ASC,
-- including publications with identical timestamps. Fetch at most one lookahead.
create function private.feed_archive_chunk(checkpoint_at timestamptz, checkpoint_id uuid)
returns setof feed.posts language sql stable set search_path='' as $$
    select candidates.* from (
        (select p.* from feed.posts p where checkpoint_id is not null
           and p.created_at=checkpoint_at and p.id>checkpoint_id
           and p.deleted_at is null and p.moderation_status='allowed'
         order by p.created_at desc,p.id limit 129)
        union all
        (select p.* from feed.posts p where p.created_at<checkpoint_at
           and p.deleted_at is null and p.moderation_status='allowed'
         order by p.created_at desc,p.id limit 129)
    ) candidates order by created_at desc,id limit 129;
$$;

create function private.feed_scroll_issue(sc recsys.feed_scrolls, p feed.posts, seed_item recsys.feed_snapshot_items,
                                          seed recsys.feed_snapshots)
returns uuid language sql set search_path='' as $$
    insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,snapshot_id,position,
                                  model,embedding_model,features,features_at,source_snapshot_id)
    values(sc.user_id,p.id,p.version,sc.epoch,'for_you',sc.id,sc.next_position,
           coalesce(seed.model,'archive-v2'),coalesce(seed.embedding_model,'none'),
           coalesce(seed_item.features,'{}'::float8[]),coalesce(seed.features_at,statement_timestamp()),seed.id)
    returning id;
$$;

create function private.get_for_you_feed_v2_impl(requested_session uuid, requested_cursor uuid, requested_limit integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
    viewer uuid:=auth.uid(); now_at timestamptz:=statement_timestamp();
    state recsys.user_states; sc recsys.feed_scrolls; page recsys.feed_scroll_pages;
    request_token uuid:=coalesce(requested_cursor,requested_session);
    seed recsys.feed_snapshots; seed_item recsys.feed_snapshot_items;
    post feed.posts; receipt recsys.deliveries; receipt_id uuid;
    receipts uuid[]:='{}'; items jsonb:='[]'; visited integer:=0;
    seed_done boolean:=false; repeat_pending boolean:=false; reasons text[];
begin
    perform private.require_social_account();
    perform private.consume_feed_quota('recommendation_read');
    if requested_session is null or requested_limit is null or requested_limit not between 1 and 30 then
        raise exception using errcode='22023',message='invalid_feed_cursor';
    end if;
    state:=private.lock_recommendation_user(viewer);
    select * into sc from recsys.feed_scrolls where request_id=requested_session and user_id=viewer for update;
    if not found then
        if requested_cursor is not null then raise exception using errcode='PT404',message='feed_session_not_found'; end if;
        select s.id into seed.id from recsys.feed_snapshots s
          where s.id=state.current_snapshot and s.user_id=viewer and s.epoch=state.epoch and s.expires_at>now_at;
        insert into recsys.feed_scrolls(request_id,user_id,epoch,seed_id,archive_at,next_token,expires_at)
          values(requested_session,viewer,state.epoch,seed.id,now_at,request_token,now_at+interval '20 minutes')
          returning * into sc;
        update recsys.feed_scrolls set expires_at=now_at where id in (
            select id from recsys.feed_scrolls where user_id=viewer and id<>sc.id and expires_at>now_at
            order by expires_at desc,id offset 3);
    elsif sc.epoch<>state.epoch then
        raise exception using errcode='PT409',message='feed_session_invalidated';
    elsif sc.expires_at<=now_at then
        raise exception using errcode='PT410',message='feed_session_expired';
    end if;

    if (requested_cursor is null or sc.seed_id is null)
       and (state.prepared_at is null or state.prepared_at<now_at-interval '30 seconds' or state.processed_revision<state.revision) then
        perform private.queue_recommendation_refresh(viewer,state.revision,true);
    end if;

    select * into page from recsys.feed_scroll_pages q where q.scroll_id=sc.id and q.token=request_token;
    if found then
        if page.page_size<>requested_limit then raise exception using errcode='22023',message='feed_page_size_changed'; end if;
    else
        if sc.next_token is distinct from request_token then raise exception using errcode='22023',message='invalid_feed_cursor'; end if;
        if sc.seed_id is not null and sc.seed_after<199 then
            select * into seed from recsys.feed_snapshots where id=sc.seed_id;
            for seed_item in select i.* from recsys.feed_snapshot_items i
                where i.snapshot_id=sc.seed_id and i.position>sc.seed_after order by i.position
            loop
                if cardinality(receipts)>=requested_limit then exit; end if;
                sc.seed_after:=seed_item.position;
                select * into post from feed.posts where id=seed_item.post_id and version=seed_item.post_version;
                if not found or not private.recommendation_post_allowed(viewer,post) then continue; end if;
                receipt_id:=private.feed_scroll_issue(sc,post,seed_item,seed);
                receipts:=array_append(receipts,receipt_id);
                insert into recsys.feed_scroll_seen values(sc.id,post.id,sc.next_position);
                sc.next_position:=sc.next_position+1;
                sc.unique_count:=sc.unique_count+1;
            end loop;
            if cardinality(receipts)<requested_limit then sc.seed_after:=199; end if;
        end if;

        if cardinality(receipts)<requested_limit and not sc.archive_done then
            for post in select p.* from private.feed_archive_chunk(sc.archive_at,sc.archive_id) p
                order by p.created_at desc,p.id
            loop
                visited:=visited+1;
                if visited>128 or cardinality(receipts)>=requested_limit then exit; end if;
                sc.archive_at:=post.created_at;
                sc.archive_id:=post.id;
                if post.author_id=viewer or exists(select 1 from recsys.feed_scroll_seen
                        where scroll_id=sc.id and post_id=post.id)
                   or not private.recommendation_post_allowed(viewer,post) then continue; end if;
                receipt_id:=private.feed_scroll_issue(sc,post,null,null);
                receipts:=array_append(receipts,receipt_id);
                insert into recsys.feed_scroll_seen values(sc.id,post.id,sc.next_position);
                sc.next_position:=sc.next_position+1;
                sc.unique_count:=sc.unique_count+1;
            end loop;
            sc.archive_done:=visited<=128 and cardinality(receipts)<requested_limit;
        end if;

        if sc.archive_done and sc.unique_count between 2 and 9 then
            -- Keep the repeat portion separate and only allow it once. Recheck
            -- the actual small inventory, including posts revoked mid-scroll.
            if (select count(*) from recsys.feed_scroll_seen seen join feed.posts p on p.id=seen.post_id
                where seen.scroll_id=sc.id and private.recommendation_post_allowed(viewer,p))>=2 then
                if cardinality(receipts)>0 then
                    repeat_pending:=true;
                else
                    for post in select p.* from recsys.feed_scroll_seen seen join feed.posts p on p.id=seen.post_id
                      where seen.scroll_id=sc.id and seen.first_position<sc.next_position-1
                        and private.recommendation_post_allowed(viewer,p)
                      order by seen.first_position limit least(2,requested_limit)
                    loop
                        receipt_id:=private.feed_scroll_issue(sc,post,null,null);
                        receipts:=array_append(receipts,receipt_id);
                        sc.next_position:=sc.next_position+1;
                    end loop;
                end if;
            end if;
        end if;

        seed_done:=sc.seed_id is null or sc.seed_after=199;
        sc.next_token:=case when not seed_done or not sc.archive_done or repeat_pending
                            then extensions.gen_random_uuid() end;
        insert into recsys.feed_scroll_pages values(sc.id,request_token,requested_limit,receipts,sc.next_token)
          returning * into page;
    end if;

    sc.expires_at:=greatest(sc.expires_at,now_at+interval '20 minutes');
    update recsys.feed_scrolls set seed_after=sc.seed_after,archive_at=sc.archive_at,archive_id=sc.archive_id,
        archive_done=sc.archive_done,next_token=sc.next_token,next_position=sc.next_position,
        unique_count=sc.unique_count,expires_at=sc.expires_at
      where id=sc.id;
    for receipt in select d.* from unnest(page.receipts) with ordinality ids(id,ord)
        join recsys.deliveries d on d.id=ids.id and d.user_id=viewer order by ids.ord
    loop
        select * into post from feed.posts where id=receipt.post_id and version=receipt.post_version;
        if not found or not private.recommendation_post_allowed(viewer,post) then continue; end if;
        if receipt.valid_until<=now_at then
            update recsys.deliveries set valid_until=now_at+interval '20 minutes'
              where id=receipt.id returning valid_until into receipt.valid_until;
        end if;
        reasons:=array['archive'];
        if receipt.source_snapshot_id is not null then
            select i.reasons into reasons from recsys.feed_snapshot_items i
              where i.snapshot_id=receipt.source_snapshot_id and i.post_id=receipt.post_id;
        end if;
        items:=items||jsonb_build_array(jsonb_build_object(
            'position',receipt.position,'delivery_id',receipt.id,'delivery_expires_at',receipt.valid_until,
            'post',private.feed_post_json(post)||jsonb_build_object('action_version',
                coalesce((select version from recsys.post_action_versions where user_id=viewer and post_id=post.id),0),
                'liked',exists(select 1 from feed.post_likes where user_id=viewer and post_id=post.id)),
            'reasons',coalesce(reasons,'{}'::text[]),'model',receipt.model));
    end loop;
    return jsonb_build_object('contract_version',2,'session_id',sc.request_id,'expires_at',sc.expires_at,'items',items,
        'has_more',page.next_token is not null,'next_cursor',page.next_token,
        'status',case when page.next_token is null then 'exhausted'
                      when jsonb_array_length(items)=0 then 'continue' else 'page' end);
end $$;

create function public.get_for_you_feed_v2(requested_session uuid, requested_cursor uuid default null,
                                           requested_limit integer default 20)
returns jsonb language sql security invoker set search_path='' as $$
    select private.get_for_you_feed_v2_impl(requested_session,requested_cursor,requested_limit);
$$;

revoke all on function private.feed_archive_chunk(timestamptz,uuid),
    private.feed_scroll_issue(recsys.feed_scrolls,feed.posts,recsys.feed_snapshot_items,recsys.feed_snapshots),
    private.get_for_you_feed_v2_impl(uuid,uuid,integer), public.get_for_you_feed_v2(uuid,uuid,integer)
    from public, anon, authenticated, service_role, yap_recommendation_worker, yap_feed_media_worker, yap_feed_vision_worker;
grant execute on function private.get_for_you_feed_v2_impl(uuid,uuid,integer),
    public.get_for_you_feed_v2(uuid,uuid,integer) to authenticated;

create or replace function recsys.cleanup_recommendations()
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer:=0; affected integer; expired uuid; pages_budget integer:=400; seen_budget integer:=2000;
begin
  -- Bound child deletions as well as parent deletions.
  for expired in select id from recsys.feed_scrolls where expires_at<=statement_timestamp()
    order by expires_at,id for update skip locked limit 25
  loop
    delete from recsys.feed_scroll_pages where scroll_id=expired and token in (
      select token from recsys.feed_scroll_pages where scroll_id=expired order by token limit pages_budget);
    get diagnostics affected=row_count;removed:=removed+affected;pages_budget:=pages_budget-affected;
    delete from recsys.feed_scroll_seen where scroll_id=expired and post_id in (
      select post_id from recsys.feed_scroll_seen where scroll_id=expired order by post_id limit seen_budget);
    get diagnostics affected=row_count;removed:=removed+affected;seen_budget:=seen_budget-affected;
    delete from recsys.feed_scrolls where id=expired
      and not exists(select 1 from recsys.feed_scroll_pages where scroll_id=expired)
      and not exists(select 1 from recsys.feed_scroll_seen where scroll_id=expired);
    get diagnostics affected=row_count;removed:=removed+affected;
    exit when pages_budget=0 or seen_budget=0;
  end loop;
  delete from recsys.feed_snapshots where id in(select s.id from recsys.feed_snapshots s
    where s.expires_at<statement_timestamp()-interval '1 hour'
      and not exists(select 1 from recsys.feed_scrolls sc where sc.seed_id=s.id)
    order by s.expires_at,s.id for update of s skip locked limit 25);
  get diagnostics affected=row_count;removed:=removed+affected;
  delete from recsys.deliveries where id in(select d.id from recsys.deliveries d
    where d.delivered_at<statement_timestamp()-interval '30 days'
      and not exists(select 1 from recsys.feed_scrolls sc where sc.id=d.snapshot_id)
    order by d.delivered_at,d.id for update of d skip locked limit 100);
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
  with inactive as(select s.user_id from recsys.user_states s where s.active_until<statement_timestamp()
    and exists(select 1 from recsys.refresh_jobs j where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp()))
    order by s.active_until,s.user_id for update skip locked limit 100)
  delete from recsys.refresh_jobs j using inactive s where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp());
  get diagnostics affected=row_count;return removed+affected;
end $$;

notify pgrst,'reload schema';
