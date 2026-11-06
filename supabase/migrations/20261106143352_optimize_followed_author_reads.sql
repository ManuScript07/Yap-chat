-- Cover the metadata needed for ordinary author candidates. Fetch full rows
-- only for quotes and the selected page; a whole-row projection prevents an
-- index-only candidate path and can scan an unrelated index for every author
-- while statistics lag behind a burst of new posts.
-- No RPC, permission predicate, ordering, quota or pagination behavior changes.
create index feed_posts_live_author_idx on feed.posts(author_id,created_at desc,id)
    include(audience,is_repost)
    where deleted_at is null and moderation_status = 'allowed';

-- Read the session exclusion set once. NOT IN hashes its non-null IDs instead
-- of repeatedly probing a growing global page_items table under a stale plan.
create or replace function private.get_friends_feed_impl(requested_session uuid,after_position integer,requested_limit integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare s feed.page_sessions%rowtype;page feed.page_metadata%rowtype;state recsys.user_states%rowtype;
 chosen uuid[];connections uuid[];items jsonb;more boolean;cursor integer;target uuid;current_post feed.posts%rowtype;delivery uuid;
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
  issued as materialized(
   select post_id from feed.page_items where session_id=s.id and post_id is not null),
  events as(
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select p.id,p.created_at from feed.posts p where p.author_id=f.id and p.created_at<=s.created_at
     and p.deleted_at is null and p.moderation_status='allowed'
     -- Connection identities were checked once above. Inline cheap row filters
     -- before the per-author limit; resolve full chains only for actual quotes.
     and(p.audience='public'or exists(select 1 from public.friendships rel
       where rel.user_one_id=least(auth.uid(),p.author_id)and rel.user_two_id=greatest(auth.uid(),p.author_id)))
     and not exists(select 1 from feed.reported_content_hides h where h.user_id=auth.uid()and h.target_type='post'and h.target_id=p.id)
     and(not p.is_repost or exists(select 1 from feed.posts quoted where quoted.id=p.id
       and private.feed_post_accessible(auth.uid(),quoted)))
     and p.id not in(select post_id from issued)
     order by p.created_at desc,p.id limit requested_limit+1
     )
    select id,created_at at from unseen
    order by created_at desc,id limit requested_limit+1)found
   union all
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select r,original from feed.reposts r join feed.posts original on original.id=r.original_post_id
     where r.author_id=f.id and r.created_at<=s.created_at and r.post_id is null
     and r.deleted_at is null and r.moderation_status='allowed'
     and r.original_post_id not in(select post_id from issued)
     order by r.created_at desc,r.id)
    select (r).original_post_id id,(r).created_at at from unseen
    where private.feed_post_visible(auth.uid(),(r).author_id,(r).audience)
    and private.feed_post_accessible(auth.uid(),original)limit requested_limit+1)found
  ),recent as(select id,max(at)at from events group by id),eligible as(
   -- Both sources already read existing posts in this statement's MVCC snapshot.
   -- Rejoining the full posts table here can turn a cached plan into a quadratic
   -- materialized nested loop. Live visibility is checked again when rendering.
   select r.id,r.at from recent r where r.id not in(select post_id from issued)
   order by r.at desc,r.id limit requested_limit+1)
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
 with friends as materialized(select unnest(connections)id),issued_page as materialized(
  select i.position,i.post_id,i.post_version,i.delivery_id from feed.page_items i
  where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position
 ),current_page as materialized(
  select i.position,selected.post,d.id delivery_id,d.valid_until delivery_expires_at,
   coalesce(v.version,0)action_version,l.post_id is not null liked
  -- The lateral LIMIT preserves the page-first lookup even when a cached plan
  -- still estimates empty tables after a burst of posts and issued pages.
  from issued_page i cross join lateral(
   select p as post from feed.posts p where p.id=i.post_id and p.version=i.post_version limit 1
  )selected
  join recsys.deliveries d on d.id=i.delivery_id and d.epoch=state.epoch and d.valid_until>statement_timestamp()
  left join recsys.post_action_versions v on v.user_id=auth.uid()and v.post_id=(selected.post).id
  left join feed.post_likes l on l.user_id=auth.uid()and l.post_id=(selected.post).id
 )select coalesce(jsonb_agg(jsonb_build_object('position',c.position,'delivery_id',c.delivery_id,
  'delivery_expires_at',c.delivery_expires_at,'post',private.feed_post_json(c.post)
    ||jsonb_build_object('action_version',c.action_version,'liked',c.liked))order by c.position),'[]')into items
 from current_page c where private.feed_post_accessible(auth.uid(),c.post)
 and(exists(select 1 from friends f where f.id=(c.post).author_id)or exists(select 1 from friends f join feed.reposts r on r.author_id=f.id
  where r.original_post_id=(c.post).id and r.post_id is null and r.created_at<=s.created_at and r.deleted_at is null and r.moderation_status='allowed'
  and private.feed_post_visible(auth.uid(),r.author_id,r.audience)));
 return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'items',items,'has_more',page.has_more,
 'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;
