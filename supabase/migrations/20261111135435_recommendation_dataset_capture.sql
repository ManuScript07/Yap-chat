-- Internal research export. No Data API endpoint or runtime worker grant.
do $$ begin
    if not exists (select 1 from pg_catalog.pg_roles where rolname='yap_recommendation_exporter') then
        create role yap_recommendation_exporter nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;
    elsif exists (select 1 from pg_catalog.pg_roles where rolname='yap_recommendation_exporter'
        and (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole or rolinherit or rolreplication or rolbypassrls)) then
        raise exception 'expected a restricted dataset role';
    end if;
end $$;

create schema recsys_dataset;
revoke all on schema recsys_dataset from public,anon,authenticated,service_role,yap_recommendation_worker,yap_feed_media_worker;
grant usage on schema recsys_dataset to yap_recommendation_exporter;
create table recsys_dataset.cohorts (
    id uuid primary key,
    origin text not null check(origin='synthetic'),
    seed bigint not null check(seed>=0),
    source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
    registered_at timestamptz not null default clock_timestamp()
);
create table recsys_dataset.members (
    cohort_id uuid not null references recsys_dataset.cohorts on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    primary key(cohort_id,user_id)
);
create index dataset_members_user_idx on recsys_dataset.members(user_id);
alter table recsys_dataset.cohorts enable row level security;
alter table recsys_dataset.members enable row level security;
revoke all on recsys_dataset.cohorts,recsys_dataset.members from public,anon,authenticated,service_role,yap_recommendation_worker,yap_feed_media_worker,yap_recommendation_exporter;

-- Per-member keyset seeks, including across interest resets.
create index feedback_facts_dataset_seek_idx on recsys.feedback_facts(user_id,sequence);

create function recsys_dataset.capture_scope(cohort uuid)
returns recsys_dataset.cohorts language plpgsql stable security invoker set search_path='' as $$
declare c recsys_dataset.cohorts; members integer;
begin
    if current_setting('transaction_isolation')<>'repeatable read'
        or current_setting('transaction_read_only')<>'on' then
        raise exception using errcode='25006',message='dataset requires read-only repeatable read';
    end if;
    select * into c from recsys_dataset.cohorts where id=cohort;
    select count(*) into members from (select 1 from recsys_dataset.members where cohort_id=cohort limit 129) m;
    if c.id is null or members not between 1 and 128 then
        raise exception using errcode='22023',message='invalid dataset cohort';
    end if;
    return c;
end $$;

create function recsys_dataset.capture_info(cohort uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c recsys_dataset.cohorts; h recsys.feedback_history_contract;
    snap pg_snapshot:=pg_current_snapshot(); writers int; matched int; oldest timestamptz;
    captured timestamptz:=transaction_timestamp(); definition_hash text;
begin
    c:=recsys_dataset.capture_scope(cohort);
    select * into strict h from recsys.feedback_history_contract;
    -- Only an aggregate leaves this function. Unmatched writers (including a
    -- prepared transaction or a commit racing this lookup) invalidate the fence.
    perform pg_stat_clear_snapshot();
    select count(*),count(a.xact_start),min(a.xact_start) into writers,matched,oldest
    from pg_snapshot_xip(snap) x
    left join pg_stat_activity a on a.backend_xid::text::bigint=(x::text::numeric % 4294967296);
    select encode(sha256(convert_to(string_agg(pg_get_functiondef(p.oid), E'\n' order by p.proname),'UTF8')),'hex')
      into definition_hash from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='recsys_dataset';
    return jsonb_build_object('schema_version',1,'feedback_contract',h.version,
        'cohort_id',c.id,'origin',c.origin,'seed',c.seed,'source_hash',c.source_hash,
        'history_start',greatest(c.registered_at,h.started_at,captured-make_interval(days=>h.retention_days)),
        'snapshot_started_at',captured,'active_writer_count',writers,'unmatched_writer_count',writers-matched,
        'settled_through',case when writers=matched then least(captured,coalesce(oldest,captured))-interval '1 microsecond' end,
        'sql_sha256',definition_hash,
        'member_sha256',(select encode(sha256(convert_to(string_agg(user_id::text,',' order by user_id),'UTF8')),'hex')
            from recsys_dataset.members where cohort_id=cohort));
end $$;

-- Require live authorization for every original and never cross the cohort.
-- Viewer preference changes (reports, hides, less similar) are outcomes, so
-- they must not retroactively remove their own otherwise authorized exposure.
create function recsys_dataset.exposure_content(cohort uuid,f recsys.feedback_facts,p feed.posts)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare current_post feed.posts:=p; visited uuid[]:=array[]::uuid[]; fingerprints jsonb:='[]'::jsonb;
    words text[]; normalized text;
begin
    if p.id is null or p.version<>f.post_version or f.epoch<>coalesce(
        (select epoch from recsys.user_states where user_id=f.user_id),1)
        or private.is_account_globally_banned(f.user_id)
        or private.is_account_pending_deletion(f.user_id) then return null; end if;
    for depth in 0..4 loop
        if current_post.id is null or current_post.id=any(visited) or current_post.deleted_at is not null
        or current_post.moderation_status<>'allowed'
        or not private.feed_post_visible(f.user_id,current_post.author_id,current_post.audience)
        or not exists(
            select 1 from recsys_dataset.members where cohort_id=cohort and user_id=current_post.author_id
        ) or (depth>0 and current_post.updated_at>
            coalesce((f.context->>'features_at')::timestamptz,f.recorded_at)) then return null; end if;
        visited:=array_append(visited,current_post.id);
        words:=regexp_split_to_array(trim(regexp_replace(lower(current_post.text),'[^[:alnum:]]+',' ','g')),' +');
        normalized:=array_to_string(words,' ');
        fingerprints:=fingerprints||jsonb_build_array(jsonb_build_object(
            'id',current_post.id,
            'text_sha256',case when normalized<>'' then encode(sha256(convert_to(normalized,'UTF8')),'hex') end,
            'text_bigrams',coalesce((select jsonb_agg(h order by h) from (
                select distinct encode(sha256(convert_to(words[i]||' '||words[i+1],'UTF8')),'hex') h
                from generate_series(1,cardinality(words)-1) i
            ) hashed),'[]'),
            'photos',coalesce((select jsonb_agg(u.sha256 order by u.position) from feed.photo_uploads u
                where u.draft_id=current_post.id and u.state='attached'),'[]')));
        if not current_post.is_repost then
            return jsonb_build_object('author_id',p.author_id,'language',p.language,'fingerprints',fingerprints);
        end if;
        select * into current_post from feed.posts where id=current_post.original_post_id;
    end loop;
    return null;
end $$;

create function recsys_dataset.capture_page(cohort uuid,after_sequence bigint,page_size integer)
returns table(sequence bigint, fact jsonb) language plpgsql stable security definer set search_path='' as $$
begin
    perform recsys_dataset.capture_scope(cohort);
    if after_sequence is null or after_sequence<0 or page_size is null or page_size not between 1 and 500 then
        raise exception using errcode='22023',message='invalid dataset page';
    end if;
    return query
    with keys as materialized (
        select candidate.sequence from recsys_dataset.members m
        cross join lateral (
            select f.sequence from recsys.feedback_facts f where f.user_id=m.user_id and f.sequence>after_sequence
            order by f.sequence limit page_size
        ) candidate
        where m.cohort_id=cohort order by candidate.sequence limit page_size
    ), page as materialized (
        select f.* from keys k join recsys.feedback_facts f on f.sequence=k.sequence
    ), allowed as materialized (
        select f.sequence,f as journal,p as post,coalesce(f.author_id,p.author_id) as owner
        from page f left join feed.posts p on p.id=f.post_id
        where f.recorded_at >= (select greatest(c.registered_at,h.started_at,transaction_timestamp()-make_interval(days=>h.retention_days))
            from recsys_dataset.cohorts c cross join recsys.feedback_history_contract h where c.id=cohort)
        and (f.post_id is null or exists(select 1 from recsys_dataset.members
            where cohort_id=cohort and user_id=coalesce(f.author_id,p.author_id)))
        and (f.target_type not in ('user','author') or exists(select 1 from recsys_dataset.members
            where cohort_id=cohort and user_id=f.target_id))
        and (f.target_type<>'comment' or f.kind='comment' or exists(select 1 from feed.comments c
            join recsys_dataset.members m on m.user_id=c.author_id and m.cohort_id=cohort where c.id=f.target_id))
    )
    select page.sequence,case when a.sequence is not null then
        -- Explicit projection: extending the journal must not extend exports.
        jsonb_build_object('sequence',f.sequence,'event_id',f.event_id,'contract_version',f.contract_version,
            'user_id',f.user_id,'epoch',f.epoch,'recorded_at',f.recorded_at,'transaction_id',f.transaction_id::text,
            'kind',f.kind,'target_type',f.target_type,'target_id',f.target_id,'target_version',f.target_version,
            'state_version',f.state_version,'post_id',f.post_id,'post_version',f.post_version,'author_id',a.owner,
            'active',f.active,'own_content',f.own_content,'delivery_id',f.delivery_id,'surface',f.surface,
            'active_ms',f.active_ms,'opened',f.opened,
            'context',case when f.kind='impression' then f.context else '{}'::jsonb end,
            'content',case when f.kind='impression' then recsys_dataset.exposure_content(cohort,f,a.post) end)
    end
    from page left join allowed a on a.sequence=page.sequence
    left join lateral (select (a.journal).*) f on a.sequence is not null
    order by page.sequence;
end $$;

revoke all on all functions in schema recsys_dataset from public,anon,authenticated,service_role,yap_recommendation_worker,yap_feed_media_worker,yap_recommendation_exporter;
grant execute on function recsys_dataset.capture_info(uuid),recsys_dataset.capture_page(uuid,bigint,integer) to yap_recommendation_exporter;
