-- Subscriptions are explicit interests, never an authorization relationship.
-- Friendship and precise-location permissions retain their existing semantics.
create table feed.author_follows (
    follower_id uuid not null references public.profiles(id) on delete cascade,
    author_id uuid not null references public.profiles(id) on delete cascade,
    following boolean not null,
    version bigint not null check (version > 0),
    followed_at timestamptz not null default statement_timestamp(),
    updated_at timestamptz not null default statement_timestamp(),
    primary key (follower_id, author_id),
    check (follower_id <> author_id)
);
-- False rows retain the action version: a late older intent cannot recreate a follow.
create index feed_following_page_idx on feed.author_follows (follower_id, author_id) where following;
create index feed_followers_page_idx on feed.author_follows (author_id, follower_id) where following;
create index feed_followed_author_fk_idx on feed.author_follows (author_id, follower_id);
create index feed_recent_following_idx on feed.author_follows (follower_id, followed_at desc, author_id) where following;
alter table feed.author_follows enable row level security;
revoke all on feed.author_follows from public, anon, authenticated, yap_recommendation_worker, yap_feed_media_worker;

create function private.feed_follow_user_visible(viewer uuid, target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
    select target is not null
        and exists (select 1 from public.profiles where id = target)
        and not private.is_account_globally_banned(target)
        and not private.is_account_pending_deletion(target)
        and not private.is_user_pair_blocked_impl(viewer, target);
$$;

create function private.feed_follow_state_json(viewer uuid, target uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'author_id', target,
        'following', coalesce(f.following, false),
        'version', coalesce(f.version, 0),
        'can_follow', target <> viewer and private.feed_follow_user_visible(viewer, target),
        'is_friend', exists (select 1 from public.friendships
            where user_one_id = least(viewer, target) and user_two_id = greatest(viewer, target)))
    from (select 1) seed left join feed.author_follows f
        on f.follower_id = viewer and f.author_id = target;
$$;

create function private.queue_feed_follow_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid;
    revision bigint;
begin
    if tg_op = 'UPDATE' and new.following = old.following then return null; end if;
    if tg_op = 'INSERT' and not new.following then return null; end if;
    if tg_op = 'DELETE' and not old.following then return null; end if;
    viewer := case when tg_op = 'DELETE' then old.follower_id else new.follower_id end;
    -- No state creation during profile cascades; a deleted reader has no work.
    if not exists (select 1 from public.profiles where id = viewer) then return null; end if;
    update recsys.user_states s set revision = s.revision + 1 where user_id = viewer
        returning s.revision into revision;
    if revision is not null then
        perform private.queue_recommendation_refresh(viewer, revision, true);
    end if;
    return null;
end $$;
create trigger feed_follow_refresh after insert or update or delete on feed.author_follows
    for each row execute function private.queue_feed_follow_change();

create function private.set_feed_author_followed_impl(
    requested_id uuid, requested_author uuid, requested_following boolean, expected_version bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    current_state feed.author_follows%rowtype;
    action_version bigint;
    changed boolean;
    result jsonb;
    fingerprint jsonb := jsonb_build_array('author_follow', requested_author, requested_following, expected_version);
begin
    perform private.require_active_account();
    if requested_author is null or requested_author = viewer or requested_following is null
        or expected_version is null or expected_version < 0 then
        raise exception using errcode = '22023', message = 'invalid_follow_action';
    end if;
    -- Same pair lock as block/unblock. Profiles precede recommendation state,
    -- avoiding a state/profile inversion with account-deletion cascades.
    perform private.lock_user_block_pair(viewer, requested_author);
    perform id from public.profiles where id in (viewer, requested_author) order by id for key share;
    perform private.require_social_account();
    perform private.consume_social_quota('follow_write');
    perform private.lock_recommendation_user(viewer);
    result := private.replay_recommendation_action(viewer, requested_id, fingerprint);
    if result is not null then return result; end if;
    if not exists (select 1 from public.profiles where id = requested_author) then
        raise exception using errcode = 'PT404', message = 'follow_target_not_found';
    end if;
    -- Unfollow remains available for an existing banned/deleting author.
    if requested_following and not private.feed_follow_user_visible(viewer, requested_author) then
        raise exception using errcode = 'PT404', message = 'follow_target_not_found';
    end if;
    select * into current_state from feed.author_follows
        where follower_id = viewer and author_id = requested_author for update;
    action_version := coalesce(current_state.version, 0);
    if action_version <> expected_version then
        raise exception using errcode = 'PT409', message = 'follow_action_version_conflict';
    end if;
    changed := coalesce(current_state.following, false) <> requested_following;
    if changed and requested_following then
        perform private.consume_social_quota('follow_create');
        if (select count(*) from feed.author_follows where follower_id = viewer and following) >= 10000 then
            raise exception using errcode = '42901', message = 'following_capacity_reached';
        end if;
    end if;
    insert into feed.author_follows as f (follower_id, author_id, following, version)
        values (viewer, requested_author, requested_following, action_version + 1)
    on conflict (follower_id, author_id) do update set
        following = excluded.following, version = excluded.version,
        followed_at = case when not f.following and excluded.following then statement_timestamp() else f.followed_at end,
        updated_at = statement_timestamp()
    returning * into current_state;
    result := jsonb_build_object('request_id', requested_id, 'author_id', requested_author,
        'following', current_state.following, 'version', current_state.version, 'changed', changed, 'replayed', false);
    insert into recsys.action_requests(user_id, id, payload, response) values (viewer, requested_id, fingerprint, result);
    return result;
end $$;

create function private.get_feed_author_follow_state_impl(requested_author uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
    perform private.require_social_account();
    perform private.consume_social_quota('follow_state_read');
    if requested_author is null or not exists (select 1 from public.profiles where id = requested_author) then
        raise exception using errcode = 'PT404', message = 'follow_target_not_found';
    end if;
    -- Only the caller's own relation, never the blocked user's profile or geo.
    return private.feed_follow_state_json(auth.uid(), requested_author);
end $$;

create function private.get_feed_follows_impl(
    requested_user uuid, after_user uuid, requested_limit integer, incoming boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    owner uuid := coalesce(requested_user, auth.uid());
    candidates uuid[];
    ids uuid[];
    items jsonb;
    more boolean;
begin
    perform private.require_social_account();
    perform private.consume_social_quota(case when incoming then 'followers_read' else 'following_read' end);
    if incoming is null or requested_limit is null or requested_limit not between 1 and 100 then
        raise exception using errcode = '22023', message = 'invalid_follows_cursor';
    end if;
    if not private.feed_follow_user_visible(auth.uid(), owner) then
        raise exception using errcode = 'PT404', message = 'follow_list_not_found';
    end if;
    -- Separate branches match the two partial indexes; no unbounded total count.
    if incoming then
        with ordered as materialized (
            select follower_id id from feed.author_follows where author_id = owner and following
                and (after_user is null or follower_id > after_user) order by follower_id)
        select array_agg(id order by id) into candidates from (
            select id from ordered where private.feed_follow_user_visible(auth.uid(), id)
                and private.feed_follow_user_visible(owner, id) limit requested_limit + 1) page;
    else
        with ordered as materialized (
            select author_id id from feed.author_follows where follower_id = owner and following
                and (after_user is null or author_id > after_user) order by author_id)
        select array_agg(id order by id) into candidates from (
            select id from ordered where private.feed_follow_user_visible(auth.uid(), id)
                and private.feed_follow_user_visible(owner, id) limit requested_limit + 1) page;
    end if;
    candidates := coalesce(candidates, '{}');
    more := cardinality(candidates) > requested_limit;
    ids := candidates[1:requested_limit];
    select coalesce(jsonb_agg(jsonb_build_object('user', jsonb_build_object('id', p.id,
        'username', p.username, 'display_name', p.display_name), 'followed_at', f.followed_at,
        'relationship', private.feed_follow_state_json(auth.uid(), p.id)) order by p.id), '[]') into items
    from unnest(ids) page(id) join public.profiles p on p.id = page.id join feed.author_follows f
        on f.follower_id = case when incoming then p.id else owner end
        and f.author_id = case when incoming then owner else p.id end;
    return jsonb_build_object('user_id', owner, 'items', items, 'has_more', more,
        'next_cursor', case when more then jsonb_build_object('requested_user', owner,
            'after_user', ids[cardinality(ids)]) else null end);
end $$;

create function private.remove_feed_follows_on_block()
returns trigger language plpgsql security definer set search_path = '' as $$
declare relation record;
begin
    perform private.lock_user_block_pair(new.blocker_user_id, new.blocked_user_id);
    -- Global UUID order when two affected readers need their refresh state locked.
    for relation in select follower_id, author_id from feed.author_follows
        where following and ((follower_id = new.blocker_user_id and author_id = new.blocked_user_id)
            or (follower_id = new.blocked_user_id and author_id = new.blocker_user_id)) order by follower_id
    loop
        update feed.author_follows set following = false, version = version + 1,
            updated_at = statement_timestamp()
            where follower_id = relation.follower_id and author_id = relation.author_id;
    end loop;
    return null;
end $$;
create trigger feed_follows_blocked after insert on public.user_blocks
    for each row execute function private.remove_feed_follows_on_block();

create function private.feed_timeline_authors(viewer uuid)
returns table(author_id uuid) language sql stable security definer set search_path = '' as $$
    select c.author_id from (
        select case when user_one_id = viewer then user_two_id else user_one_id end author_id
            from public.friendships where user_one_id = viewer or user_two_id = viewer
        union
        select f.author_id from feed.author_follows f where f.follower_id = viewer and f.following
    ) c where private.feed_follow_user_visible(viewer, c.author_id);
$$;

create function public.set_feed_author_followed(requested_id uuid, requested_author uuid,
    requested_following boolean, expected_version bigint)
returns jsonb language sql security invoker set search_path = '' as $$
    select private.set_feed_author_followed_impl(requested_id, requested_author, requested_following, expected_version);
$$;
create function public.get_feed_author_follow_state(requested_author uuid)
returns jsonb language sql security invoker set search_path = '' as $$
    select private.get_feed_author_follow_state_impl(requested_author);
$$;
create function public.get_feed_following(requested_user uuid default null, after_user uuid default null, requested_limit integer default 30)
returns jsonb language sql security invoker set search_path = '' as $$
    select private.get_feed_follows_impl(requested_user, after_user, requested_limit, false);
$$;
create function public.get_feed_followers(requested_user uuid default null, after_user uuid default null, requested_limit integer default 30)
returns jsonb language sql security invoker set search_path = '' as $$
    select private.get_feed_follows_impl(requested_user, after_user, requested_limit, true);
$$;

create or replace function private.consume_social_quota(op text)
returns void language plpgsql security definer set search_path=''as $$
declare per_min integer;per_day integer;accepted integer;today date:=(statement_timestamp()at time zone 'UTC')::date;
begin
 case op
 when 'follow_write' then per_min:=120;per_day:=2000;
 when 'follow_create' then per_min:=30;per_day:=500;
 when 'follow_state_read' then per_min:=120;per_day:=86400;
 when 'following_read' then per_min:=60;per_day:=86400;
 when 'followers_read' then per_min:=60;per_day:=86400;
 when 'comment_create' then per_min:=30;per_day:=500;
 when 'comment_create_request' then per_min:=60;per_day:=86400;
 when 'comment_edit' then per_min:=30;per_day:=1000;
 when 'comment_delete' then per_min:=60;per_day:=1000;
 when 'comment_action' then per_min:=120;per_day:=20000;
 when 'comment_read' then per_min:=60;per_day:=86400;
 when 'report_post' then per_min:=5;per_day:=20;
 when 'report_comment' then per_min:=5;per_day:=30;
 when 'report_request' then per_min:=60;per_day:=86400;
 when 'friends_read' then per_min:=60;per_day:=86400;
 else raise exception using errcode='22023',message='invalid_social_operation';end case;
 insert into private.feed_social_limits as q(user_id,operation,window_started_at,requests,day_utc,day_count)
 values(auth.uid(),op,statement_timestamp(),1,today,1)
 on conflict(user_id,operation)do update set
 window_started_at=case when q.window_started_at<=statement_timestamp()-interval '1 minute'then statement_timestamp()else q.window_started_at end,
 requests=case when q.window_started_at<=statement_timestamp()-interval '1 minute'then 1 else q.requests+1 end,
 day_utc=today,day_count=case when q.day_utc<today then 1 else q.day_count+1 end
 where(q.window_started_at<=statement_timestamp()-interval '1 minute'or q.requests<per_min)and(q.day_utc<today or q.day_count<per_day)
 returning requests into accepted;
 if accepted is null then raise exception using errcode='42901',message='social_rate_limited';end if;
end $$;

create or replace function private.get_friends_feed_impl(requested_session uuid,after_position integer,requested_limit integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare s feed.page_sessions%rowtype;page feed.page_metadata%rowtype;state recsys.user_states%rowtype;
 chosen uuid[];connections uuid[];items jsonb;more boolean;cursor integer;target uuid;current_post feed.posts%rowtype;delivery uuid;expires timestamptz;
begin
 perform private.require_social_account();perform private.consume_social_quota('friends_read');
 if requested_limit is null or requested_limit not between 1 and 30 or after_position is null or after_position< -1 then
 raise exception using errcode='22023',message='invalid_friends_cursor';end if;
 state:=private.lock_recommendation_user(auth.uid());
 if requested_session is null then
  if after_position<> -1 then raise exception using errcode='22023',message='invalid_friends_cursor';end if;
  if(select count(*)from feed.page_sessions where user_id=auth.uid()and expires_at>statement_timestamp())>=128 then
   raise exception using errcode='42901',message='feed_sessions_rate_limited';end if;
  insert into feed.page_sessions(id,user_id,sort,page_size,epoch)values(extensions.gen_random_uuid(),auth.uid(),'friends',requested_limit,state.epoch)returning * into s;
 else
  select * into s from feed.page_sessions where id=requested_session and user_id=auth.uid()for update;
  if not found then raise exception using errcode='PT404',message='friends_session_not_found';end if;
  if s.epoch<>state.epoch then raise exception using errcode='PT409',message='friends_session_invalidated';end if;
  if s.sort<>'friends'or s.page_size<>requested_limit then raise exception using errcode='22023',message='friends_cursor_context_mismatch';end if;
  if s.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='friends_session_expired';end if;
 end if;
 select array_agg(author_id)into connections from private.feed_timeline_authors(auth.uid());
 select * into page from feed.page_metadata where session_id=s.id and page_metadata.after_position=get_friends_feed_impl.after_position;
 if not found then
  if after_position<>s.next_position-1 then raise exception using errcode='22023',message='invalid_friends_cursor';end if;
  with friends as materialized(select unnest(connections)id),
  events as(
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select p from feed.posts p where p.author_id=f.id and p.created_at<=s.created_at
     and p.deleted_at is null and p.moderation_status='allowed'
     -- Connection identities were checked once above. Inline cheap row filters
     -- before the per-author limit; resolve full chains only for actual quotes.
     and(p.audience='public'or exists(select 1 from public.friendships rel
       where rel.user_one_id=least(auth.uid(),p.author_id)and rel.user_two_id=greatest(auth.uid(),p.author_id)))
     and not exists(select 1 from feed.reported_content_hides h where h.user_id=auth.uid()and h.target_type='post'and h.target_id=p.id)
     and(not p.is_repost or private.feed_post_accessible(auth.uid(),p))
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
     order by p.created_at desc,p.id)
    select (p).id,(p).created_at at from unseen
    limit requested_limit+1)found
   union all
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select r,original from feed.reposts r join feed.posts original on original.id=r.original_post_id
     where r.author_id=f.id and r.created_at<=s.created_at and r.post_id is null
     and r.deleted_at is null and r.moderation_status='allowed'
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=r.original_post_id)
     order by r.created_at desc,r.id)
    select (r).original_post_id id,(r).created_at at from unseen
    where private.feed_post_visible(auth.uid(),(r).author_id,(r).audience)
    and private.feed_post_accessible(auth.uid(),original)limit requested_limit+1)found
  ),recent as(select id,max(at)at from events group by id),eligible as(
   select p.id,r.at from recent r join feed.posts p on p.id=r.id where
   not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
   order by r.at desc,p.id limit requested_limit+1)
  select array_agg(id order by at desc,id)into chosen from eligible;
  chosen:=coalesce(chosen,'{}');more:=cardinality(chosen)>requested_limit;chosen:=chosen[1:requested_limit];cursor:=s.next_position;
  foreach target in array chosen loop
   select * into current_post from feed.posts where id=target;
   insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
   values(auth.uid(),current_post.id,current_post.version,state.epoch,'friends','friends-v1',
    'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query')returning id into delivery;
   insert into feed.page_items(session_id,position,post_id,post_version,delivery_id)values(s.id,cursor,current_post.id,current_post.version,delivery);cursor:=cursor+1;
  end loop;
  update feed.page_sessions set next_position=cursor where id=s.id;
  insert into feed.page_metadata(session_id,after_position,last_position,has_more)values(s.id,after_position,cursor-1,more)returning * into page;
 end if;
 with friends as materialized(select unnest(connections)id)
 select coalesce(jsonb_agg(jsonb_build_object('position',i.position,'delivery_id',d.id,'delivery_expires_at',d.valid_until,
 'post',private.feed_post_json(p)||jsonb_build_object('action_version',coalesce(v.version,0),'liked',l.post_id is not null))order by i.position),'[]')into items
 from feed.page_items i join feed.posts p on p.id=i.post_id and p.version=i.post_version
 join recsys.deliveries d on d.id=i.delivery_id and d.epoch=state.epoch and d.valid_until>statement_timestamp()
 left join recsys.post_action_versions v on v.user_id=auth.uid()and v.post_id=p.id
 left join feed.post_likes l on l.user_id=auth.uid()and l.post_id=p.id
 where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position and private.feed_post_accessible(auth.uid(),p)
 and(exists(select 1 from friends f where f.id=p.author_id)or exists(select 1 from friends f join feed.reposts r on r.author_id=f.id
 where r.original_post_id=p.id and r.post_id is null and r.created_at<=s.created_at and r.deleted_at is null and r.moderation_status='allowed'
 and private.feed_post_visible(auth.uid(),r.author_id,r.audience)));
 return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'items',items,'has_more',page.has_more,
 'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;

create or replace function private.feed_post_json_depth(p feed.posts,depth integer)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare result jsonb;original feed.posts%rowtype;context jsonb;
begin
 if depth>4 or not private.feed_post_accessible(auth.uid(),p)then return null;end if;
 result:=private.base_feed_post_json(p);
 if p.is_repost then
  select * into original from feed.posts where id=p.original_post_id;
  result:=result||jsonb_build_object('original',private.feed_post_json_depth(original,depth+1));
 end if;
 select coalesce(jsonb_agg(to_jsonb(chosen)),'[]')into context from(select r.id repost_id,r.author_id,u.username,r.created_at
 from feed.reposts r join public.profiles u on u.id=r.author_id where r.original_post_id=p.id and r.post_id is null
 and r.deleted_at is null and r.moderation_status='allowed'and r.author_id<>auth.uid()
 and (exists(select 1 from public.friendships f where f.user_one_id=least(auth.uid(),r.author_id)and f.user_two_id=greatest(auth.uid(),r.author_id))or exists(select 1 from feed.author_follows f where f.follower_id=auth.uid()and f.author_id=r.author_id and f.following))and private.feed_post_visible(auth.uid(),r.author_id,r.audience)
 order by r.created_at desc,r.id limit 3)chosen;
 return result||jsonb_build_object('author_relationship',private.feed_follow_state_json(auth.uid(),p.author_id),'is_repost',p.is_repost,'reposted_by',context,
 'my_repost',(select jsonb_build_object('id',r.id,'version',r.version)from feed.reposts r where r.author_id=auth.uid()and r.original_post_id=p.id and r.post_id is null and r.deleted_at is null and r.moderation_status='allowed'),
 'comment_count',coalesce((select comment_count from recsys.post_statistics where post_id=p.id),0),
 'repost_count',coalesce((select reposts from recsys.post_statistics where post_id=p.id),0));
end $$;

create or replace function recsys.load_refresh_profile(viewer uuid, requested_lease uuid, requested_model text)
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
    union all
    (select f.post_id,f.post_version,case f.kind when 'repost'then 3.0 when 'comment'then 1.2 else .4 end::float8,f.created_at
      from recsys.social_feedback f,s where f.user_id=viewer and f.epoch=s.epoch
      and f.created_at>statement_timestamp()-interval '30 days'and private.social_feedback_allowed(viewer,f)
      order by f.created_at desc,f.post_id limit 300)
    union all
    -- Explicit follows remain a current intent after an interests reset. Sample
    -- at most two live texts per author and 100 authors, never all user/post pairs.
    (select p.id,p.version,1.0::float8,greatest(f.followed_at,p.created_at)
      from (select author_id,followed_at from feed.author_follows
        where follower_id=viewer and following and private.feed_follow_user_visible(viewer,author_id)
        order by followed_at desc,author_id limit 100) f
      cross join lateral(
        select post.* from feed.posts post where post.author_id=f.author_id
          and post.text<>''and post.created_at>statement_timestamp()-interval '30 days'
          and private.feed_post_accessible(viewer,post)
        order by post.created_at desc,post.id limit 2)p)
  ), grouped as (
    select post_id,post_version,case when min(weight)<0 then -3 else least(5,sum(weight)) end weight,max(at)at
      from raw group by post_id,post_version order by max(at)desc,post_id limit 300
  ), eligible as materialized(
    select g.* from grouped g join feed.posts p on p.id=g.post_id and p.version=g.post_version
    where p.author_id<>viewer and p.deleted_at is null and p.moderation_status='allowed'
      and private.feed_post_accessible(viewer,p)
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
      coalesce(st.likes,0)likes,coalesce(st.reposts,0)reposts,seen.at is not null seen
    from ids join feed.posts p on p.id=ids.id join allowed a on a.author_id=p.author_id and a.audience=p.audience
    left join recsys.post_embeddings em on em.post_id=p.id and em.post_version=p.version and em.model=requested_model
    left join recsys.post_statistics st on st.post_id=p.id left join seen on seen.post_id=p.id
    where p.author_id<>viewer and private.feed_post_accessible(viewer,p)
      and p.created_at>statement_timestamp()-interval '7 days'
      and not exists(select 1 from recsys.hidden_authors h where h.user_id=viewer and h.author_id=p.author_id)
      and not exists(select 1 from recsys.semantic_suppressions h where h.user_id=viewer and h.post_id=p.id)
    order by p.id limit 1200
  )select coalesce(jsonb_agg(to_jsonb(c)order by c.id),'[]'::jsonb)into result from candidates c;
  return result;
end $$;

-- Every new function starts closed; only checked entrypoints are granted.
do $$
declare signature text;
begin
    foreach signature in array array[
        'private.feed_follow_user_visible(uuid,uuid)', 'private.feed_follow_state_json(uuid,uuid)',
        'private.queue_feed_follow_change()', 'private.remove_feed_follows_on_block()',
        'private.feed_timeline_authors(uuid)',
        'private.set_feed_author_followed_impl(uuid,uuid,boolean,bigint)',
        'private.get_feed_author_follow_state_impl(uuid)',
        'private.get_feed_follows_impl(uuid,uuid,integer,boolean)',
        'public.set_feed_author_followed(uuid,uuid,boolean,bigint)',
        'public.get_feed_author_follow_state(uuid)',
        'public.get_feed_following(uuid,uuid,integer)', 'public.get_feed_followers(uuid,uuid,integer)'
    ] loop
        execute 'revoke all on function ' || signature || ' from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker';
    end loop;
end $$;
grant execute on function private.set_feed_author_followed_impl(uuid,uuid,boolean,bigint),
    private.get_feed_author_follow_state_impl(uuid), private.get_feed_follows_impl(uuid,uuid,integer,boolean),
    public.set_feed_author_followed(uuid,uuid,boolean,bigint), public.get_feed_author_follow_state(uuid),
    public.get_feed_following(uuid,uuid,integer), public.get_feed_followers(uuid,uuid,integer) to authenticated;
notify pgrst, 'reload schema';
