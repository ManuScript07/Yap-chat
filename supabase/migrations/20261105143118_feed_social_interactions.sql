-- Social content remains in the shared Supabase backend. Public invoker RPCs
-- delegate to checked private functions; neither clients nor workers get DML.
alter table feed.posts add column is_repost boolean not null default false,
  add column original_post_id uuid references feed.posts(id)on delete set null;
create index feed_posts_original_idx on feed.posts(original_post_id)where original_post_id is not null;
alter table feed.posts drop constraint posts_content_check;
alter table feed.posts add constraint posts_content_check check(char_length(text)<=1000 and
  (text=''or text~'[^[:space:]]')and(text<>''or photo_count>0 or is_repost)and(not is_repost or photo_count=0));

create table feed.reposts(
 id uuid primary key,author_id uuid not null references public.profiles(id)on delete cascade,
 original_post_id uuid not null references feed.posts(id)on delete cascade,
 original_version integer not null,post_id uuid references feed.posts(id)on delete cascade,
 audience text not null check(audience in('public','friends')),creation_request jsonb not null,
 version integer not null default 1,moderation_status text not null default 'allowed'check(moderation_status in('allowed','hidden')),
 created_at timestamptz not null default statement_timestamp(),deleted_at timestamptz
);
create unique index feed_plain_repost_once_idx on feed.reposts(author_id,original_post_id)where post_id is null and deleted_at is null;
create index feed_reposts_original_idx on feed.reposts(original_post_id,created_at desc,id);
create index feed_reposts_author_idx on feed.reposts(author_id,created_at desc,id);
create index feed_reposts_post_idx on feed.reposts(post_id)where post_id is not null;
alter table recsys.post_statistics add column comment_count bigint not null default 0 check(comment_count>=0),
 add column reposts bigint not null default 0 check(reposts>=0);

create table feed.comments(
  id uuid primary key, post_id uuid not null references feed.posts(id)on delete cascade,
  root_id uuid not null, reply_to_id uuid, author_id uuid references public.profiles(id)on delete set null,
  text text not null check(char_length(text)<=200),
  version integer not null default 1 check(version>0), post_version integer not null,
  creation_request jsonb not null,
  moderation_status text not null default 'allowed'check(moderation_status in('allowed','hidden')),
  created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),deleted_at timestamptz,
  unique(id,post_id),unique(id,root_id,post_id),
  foreign key(root_id,post_id)references feed.comments(id,post_id)on delete cascade,
  foreign key(reply_to_id,root_id,post_id)references feed.comments(id,root_id,post_id)deferrable initially deferred,
  check((root_id=id and reply_to_id is null)or(root_id<>id and reply_to_id is not null)),
  check(deleted_at is not null or(text<>''and text~'[^[:space:]]'))
);
create index feed_comments_author_idx on feed.comments(author_id,id);
create index feed_comments_post_idx on feed.comments(post_id,id);
create index feed_comments_roots_idx on feed.comments(post_id,created_at,id)where root_id=id;
create index feed_comments_replies_idx on feed.comments(root_id,created_at,id)where root_id<>id;
create index feed_comments_reply_target_idx on feed.comments(reply_to_id,root_id,post_id)where reply_to_id is not null;
create table feed.comment_statistics(
  comment_id uuid primary key references feed.comments(id)on delete cascade,
  post_id uuid not null references feed.posts(id)on delete cascade,
  is_root boolean not null,created_at timestamptz not null,
  likes bigint not null default 0 check(likes>=0),replies bigint not null default 0 check(replies>=0)
);
create index feed_comment_popular_idx on feed.comment_statistics(post_id,likes desc,created_at desc,comment_id)where is_root;
create index feed_comment_stats_post_idx on feed.comment_statistics(post_id,comment_id);
create table feed.comment_likes(
 user_id uuid not null references public.profiles(id)on delete cascade,
 comment_id uuid not null references feed.comments(id)on delete cascade,
 comment_version integer not null,post_version integer not null,epoch integer not null,
 created_at timestamptz not null default statement_timestamp(),primary key(user_id,comment_id)
);
create index feed_comment_likes_comment_idx on feed.comment_likes(comment_id,user_id);
create table feed.comment_action_versions(
 user_id uuid not null references public.profiles(id)on delete cascade,
 comment_id uuid not null references feed.comments(id)on delete cascade,
 version bigint not null check(version>0),primary key(user_id,comment_id)
);
create index feed_comment_versions_comment_idx on feed.comment_action_versions(comment_id,user_id);
create table feed.page_sessions(
 id uuid primary key,user_id uuid not null references public.profiles(id)on delete cascade,
 post_id uuid references feed.posts(id)on delete cascade,root_id uuid references feed.comments(id)on delete cascade,
 sort text not null check(sort in('popular','old','new','friends')),page_size integer not null check(page_size between 1 and 30),
 created_at timestamptz not null default statement_timestamp(),expires_at timestamptz not null default statement_timestamp()+interval '20 minutes',
 epoch integer,next_position integer not null default 0,check((sort='friends')=(post_id is null)),check(sort<>'friends'or root_id is null)
);
create index feed_comment_sessions_expiry_idx on feed.page_sessions(expires_at,id);
create index feed_comment_sessions_user_idx on feed.page_sessions(user_id,expires_at,id);
create index feed_comment_sessions_post_idx on feed.page_sessions(post_id,id);
create index feed_comment_sessions_root_idx on feed.page_sessions(root_id,id);
create table feed.page_items(
 session_id uuid not null references feed.page_sessions(id)on delete cascade,
 position integer not null,comment_id uuid references feed.comments(id)on delete cascade,
 post_id uuid references feed.posts(id)on delete cascade,post_version integer,
 delivery_id uuid references recsys.deliveries(id)on delete set null,
 check((comment_id is null)<>(post_id is null)),
 primary key(session_id,position),unique(session_id,comment_id),unique(session_id,post_id)
);
create index feed_page_items_post_idx on feed.page_items(post_id,session_id)where post_id is not null;
create index feed_page_items_delivery_idx on feed.page_items(delivery_id)where delivery_id is not null;
create index feed_comment_session_items_comment_idx on feed.page_items(comment_id,session_id);
create table feed.page_metadata(
 session_id uuid not null references feed.page_sessions(id)on delete cascade,
 after_position integer not null,last_position integer not null,has_more boolean not null,
 primary key(session_id,after_position)
);
create table feed.reported_content_hides(
 user_id uuid not null references public.profiles(id)on delete cascade,
 target_type text not null check(target_type in('post','comment')),target_id uuid not null,
 created_at timestamptz not null default statement_timestamp(),primary key(user_id,target_type,target_id)
);
create table recsys.social_feedback(
 user_id uuid not null references public.profiles(id)on delete cascade,
 post_id uuid not null references feed.posts(id)on delete cascade,post_version integer not null,epoch integer not null,
 kind text not null check(kind in('comment','comment_like','repost')),entity_id uuid not null,
 created_at timestamptz not null default statement_timestamp(),primary key(user_id,kind,entity_id)
);
create index recsys_social_feedback_recent_idx on recsys.social_feedback(user_id,created_at desc,post_id);
create index recsys_social_feedback_post_idx on recsys.social_feedback(post_id,user_id);
create table private.feed_social_limits(
 user_id uuid not null references public.profiles(id)on delete cascade,operation text not null,
 window_started_at timestamptz not null,requests integer not null,day_utc date not null,day_count integer not null,
 primary key(user_id,operation)
);

alter table private.user_reports add column target_type text not null default 'user'check(target_type in('user','post','comment')),
 add column content_id uuid,add column content_snapshot jsonb,
 add constraint user_reports_content_target_check check((target_type='user'and content_id is null and content_snapshot is null)
 or(target_type<>'user'and content_id is not null and jsonb_typeof(content_snapshot)='object'));
-- IDs intentionally survive content deletion; a private snapshot retains the
-- moderator's context. Account removal keeps the existing report FK lifecycle.
create index user_reports_content_recent_idx on private.user_reports(reporter_user_id,target_type,content_id,created_at desc)where target_type<>'user';

create function private.require_social_account()
returns void language plpgsql security definer set search_path=''as $$
begin
 perform private.require_active_account();
 perform 1 from public.profiles where id=auth.uid()for key share;
 if not found then raise exception using errcode='42501',message='account_unavailable';end if;
end $$;
create function private.consume_social_quota(op text)
returns void language plpgsql security definer set search_path=''as $$
declare per_min integer;per_day integer;accepted integer;today date:=(statement_timestamp()at time zone 'UTC')::date;
begin
 case op
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

-- Up to four references, with no mutable reference links. Every hop has its
-- own current visibility/moderation/block checks; cached snapshots grant none.
create function private.feed_post_accessible(viewer uuid,p feed.posts,recommended boolean default false)
returns boolean language plpgsql stable security definer set search_path=''as $$
declare current_post feed.posts%rowtype:=p;visited uuid[]:='{}';
begin
 if viewer is null or not exists(select 1 from public.profiles where id=viewer)
 or private.is_account_globally_banned(viewer)or private.is_account_pending_deletion(viewer)then return false;end if;
 for depth in 0..4 loop
  if current_post.id is null or current_post.id=any(visited)or current_post.deleted_at is not null or current_post.moderation_status<>'allowed'
  or not private.feed_post_visible(viewer,current_post.author_id,current_post.audience)
  or exists(select 1 from feed.reported_content_hides where user_id=viewer and target_type='post'and target_id=current_post.id)then return false;end if;
  if recommended and(exists(select 1 from recsys.hidden_authors where user_id=viewer and author_id=current_post.author_id)
    or exists(select 1 from recsys.semantic_suppressions where user_id=viewer and post_id=current_post.id))then return false;end if;
  if not current_post.is_repost then return true;end if;
  visited:=array_append(visited,current_post.id);
  select * into current_post from feed.posts where id=current_post.original_post_id;
 end loop;
 return false;
end $$;
create or replace function private.recommendation_post_allowed(viewer uuid,p feed.posts)
returns boolean language sql stable security definer set search_path=''as $$select private.feed_post_accessible(viewer,p,true);$$;
create function private.semantic_feed_post(target uuid)
returns uuid language plpgsql stable security definer set search_path=''as $$
declare p feed.posts%rowtype;
begin
 for depth in 0..4 loop
  select * into p from feed.posts where id=target;
  if not found then return null;end if;
  if p.text<>''or not p.is_repost then return p.id;end if;
  target:=p.original_post_id;
 end loop;return null;
end $$;
create function private.feed_social_feedback_change()
returns trigger language plpgsql security definer set search_path=''as $$
declare viewer uuid:=case when tg_op='INSERT'then new.user_id else old.user_id end;
 target uuid:=case when tg_op='INSERT'then new.post_id else old.post_id end;rev bigint;
begin
 if not exists(select 1 from public.profiles where id=viewer)or not exists(select 1 from feed.posts where id=target)then return null;end if;
 perform private.lock_recommendation_user(viewer);
 update recsys.user_states set revision=revision+1 where user_id=viewer returning revision into rev;
 perform private.queue_recommendation_refresh(viewer,rev);return null;
end $$;
create trigger feed_social_feedback_outbox after insert or delete on recsys.social_feedback for each row execute function private.feed_social_feedback_change();
create function private.capture_feed_comment()
returns trigger language plpgsql security definer set search_path=''as $$
declare s recsys.user_states%rowtype;
begin
 if tg_op='INSERT'then
  insert into recsys.post_statistics as st(post_id,comment_count)values(new.post_id,1)
  on conflict(post_id)do update set comment_count=st.comment_count+1;
  insert into feed.comment_statistics(comment_id,post_id,is_root,created_at)values(new.id,new.post_id,new.root_id=new.id,new.created_at);
  if new.root_id<>new.id then update feed.comment_statistics set replies=replies+1 where comment_id=new.root_id;end if;
  if exists(select 1 from public.profiles where id=new.author_id)then
   s:=private.lock_recommendation_user(new.author_id);
   insert into recsys.social_feedback(user_id,post_id,post_version,epoch,kind,entity_id)
   values(new.author_id,new.post_id,new.post_version,s.epoch,'comment',new.id);
  end if;
 elsif tg_op='DELETE'then
  if old.deleted_at is null and old.moderation_status='allowed'and old.author_id is not null then update recsys.post_statistics set comment_count=greatest(0,comment_count-1)where post_id=old.post_id;end if;
  if old.root_id<>old.id then update feed.comment_statistics set replies=greatest(0,replies-1)where comment_id=old.root_id;end if;
  delete from recsys.social_feedback where kind='comment'and entity_id=old.id;
 else
  if(old.deleted_at is null and old.moderation_status='allowed'and old.author_id is not null)
   is distinct from(new.deleted_at is null and new.moderation_status='allowed'and new.author_id is not null)then
   update recsys.post_statistics set comment_count=greatest(0,comment_count+case when new.deleted_at is null and new.moderation_status='allowed'and new.author_id is not null then 1 else -1 end)where post_id=new.post_id;
  end if;
  if new.deleted_at is not null or new.moderation_status<>'allowed'or new.author_id is null then
   delete from recsys.social_feedback where kind='comment'and entity_id=new.id;
  end if;
 end if;
 return null;
end $$;
create trigger feed_comment_feedback after insert or delete or update of deleted_at,moderation_status,author_id on feed.comments for each row execute function private.capture_feed_comment();
create function private.anonymize_feed_comment()
returns trigger language plpgsql set search_path=''as $$
begin
 if new.author_id is null and old.author_id is not null then
  new.text:='';new.deleted_at:=coalesce(new.deleted_at,statement_timestamp());new.version:=old.version+1;new.updated_at:=statement_timestamp();
 end if;return new;
end $$;
create trigger feed_comment_author_removed before update of author_id on feed.comments for each row execute function private.anonymize_feed_comment();
create function private.capture_feed_comment_like()
returns trigger language plpgsql security definer set search_path=''as $$
declare viewer uuid:=case when tg_op='INSERT'then new.user_id else old.user_id end;
 target uuid:=case when tg_op='INSERT'then new.comment_id else old.comment_id end;c feed.comments%rowtype;
begin
 select * into c from feed.comments where id=target;
 if not found then return null;end if;
 update feed.comment_statistics set likes=greatest(0,likes+case when tg_op='INSERT'then 1 else -1 end)where comment_id=target;
 if tg_op='INSERT'then
  insert into recsys.social_feedback(user_id,post_id,post_version,epoch,kind,entity_id)
  values(new.user_id,c.post_id,new.post_version,new.epoch,'comment_like',new.comment_id)on conflict do nothing;
 else delete from recsys.social_feedback where user_id=viewer and kind='comment_like'and entity_id=target;end if;
 return null;
end $$;
create trigger feed_comment_like_feedback after insert or delete on feed.comment_likes for each row execute function private.capture_feed_comment_like();

create function private.feed_comment_body_allowed(viewer uuid,c feed.comments)
returns boolean language sql stable security definer set search_path=''as $$
 select c.author_id is not null and c.deleted_at is null and c.moderation_status='allowed'
 and not private.is_account_globally_banned(c.author_id)and not private.is_account_pending_deletion(c.author_id)
 and not private.is_user_pair_blocked_impl(viewer,c.author_id)
 and not exists(select 1 from feed.reported_content_hides where user_id=viewer and target_type='comment'and target_id=c.id);
$$;

-- Batch projection: names and per-viewer reactions are joined once for a page.
create function private.feed_comment_rows(viewer uuid,ids uuid[])
returns table(id uuid,body jsonb)language sql stable security definer set search_path=''as $$
 with chosen as materialized(select * from feed.comments where id=any(ids)),
 identities as materialized(select author_id id from chosen union select target.author_id from chosen c join feed.comments target on target.id=c.reply_to_id),
 visible_users as materialized(select p.id,p.username,p.display_name from identities i join public.profiles p on p.id=i.id
 where not private.is_account_globally_banned(p.id)and not private.is_account_pending_deletion(p.id)and not private.is_user_pair_blocked_impl(viewer,p.id)),
 projection as(select c.*,p.version current_post_version,u.id visible_author,u.username,u.display_name,
 not(c.deleted_at is null and c.moderation_status='allowed'and u.id is not null and hidden.target_id is null)unavailable,
 target.deleted_at target_deleted,target.moderation_status target_moderation,tu.id target_user,tu.username target_username,
 coalesce(st.likes,0)likes,coalesce(st.replies,0)replies,coalesce(v.version,0)action_version,l.comment_id is not null liked
 from chosen c join feed.posts p on p.id=c.post_id left join visible_users u on u.id=c.author_id
 left join feed.comments target on target.id=c.reply_to_id left join visible_users tu on tu.id=target.author_id
 left join feed.reported_content_hides hidden on hidden.user_id=viewer and hidden.target_type='comment'and hidden.target_id=c.id
 left join feed.comment_statistics st on st.comment_id=c.id
 left join feed.comment_action_versions v on v.user_id=viewer and v.comment_id=c.id
 left join feed.comment_likes l on l.user_id=viewer and l.comment_id=c.id)
 select c.id,jsonb_build_object('id',c.id,'post_id',c.post_id,'root_id',c.root_id,'version',c.version,'post_version',c.current_post_version,
 'text',case when c.unavailable then null else c.text end,
 'author',case when c.unavailable then null else jsonb_build_object('id',c.visible_author,'username',c.username,'display_name',c.display_name)end,
 'state',case when c.deleted_at is not null then 'deleted'when c.unavailable then 'unavailable'else 'active'end,
 'reply_to',case when c.unavailable or c.target_user is null or c.target_deleted is not null or c.target_moderation<>'allowed'then null
 else jsonb_build_object('comment_id',c.reply_to_id,'user_id',c.target_user,'username',c.target_username)end,
 'created_at',c.created_at,'updated_at',c.updated_at,'like_count',case when c.unavailable then 0 else c.likes end,
 'reply_count',c.replies,'liked',case when c.unavailable then false else c.liked end,'action_version',c.action_version)from projection c;
$$;

create function private.create_feed_comment_impl(requested_id uuid,requested_post uuid,requested_text text,requested_reply_to uuid)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;c feed.comments%rowtype;target feed.comments%rowtype;root uuid;result jsonb;
 fingerprint jsonb:=jsonb_build_array(requested_post,requested_text,requested_reply_to);
begin
 perform private.require_social_account();perform private.consume_social_quota('comment_create_request');
 if requested_id is null or requested_post is null or requested_text is null or char_length(requested_text)not between 1 and 200
 or requested_text!~'[^[:space:]]'then raise exception using errcode='22023',message='invalid_comment';end if;
 perform private.lock_recommendation_user(auth.uid());
 perform pg_advisory_xact_lock(hashtextextended('comment-create:'||requested_id::text,0));
 select * into p from feed.posts where id=requested_post for share;
 if not found or not private.feed_post_accessible(auth.uid(),p)then raise exception using errcode='PT404',message='post_not_found';end if;
 select * into c from feed.comments where id=requested_id;
 if found then
  if c.author_id is distinct from auth.uid()or c.creation_request<>fingerprint then raise exception using errcode='23505',message='comment_id_conflict';end if;
 else
  root:=requested_id;
  if requested_reply_to is not null then
   select * into target from feed.comments where id=requested_reply_to and post_id=p.id for share;
   if not found then raise exception using errcode='22023',message='invalid_comment_thread';end if;
   if target.moderation_status<>'allowed'or exists(select 1 from feed.reported_content_hides where user_id=auth.uid()and target_type='comment'and target_id=target.id)
   or(target.author_id is not null and(private.is_account_globally_banned(target.author_id)or private.is_account_pending_deletion(target.author_id)
   or private.is_user_pair_blocked_impl(auth.uid(),target.author_id)))then raise exception using errcode='PT404',message='comment_not_found';end if;
   root:=target.root_id;
  end if;
  perform private.consume_social_quota('comment_create');
  insert into feed.comments(id,post_id,root_id,reply_to_id,author_id,text,post_version,creation_request)
  values(requested_id,p.id,root,requested_reply_to,auth.uid(),requested_text,p.version,fingerprint)returning * into c;
 end if;
 select body into result from private.feed_comment_rows(auth.uid(),array[c.id]);return result;
end $$;
create function private.mutate_feed_comment_impl(requested_id uuid,requested_comment uuid,expected_version integer,requested_text text,deleting boolean)
returns jsonb language plpgsql security definer set search_path=''as $$
declare c feed.comments%rowtype;p feed.posts%rowtype;result jsonb;
 fingerprint jsonb:=jsonb_build_array('comment_mutation',requested_comment,expected_version,requested_text,deleting);
begin
 perform private.require_social_account();perform private.consume_social_quota(case when deleting then 'comment_delete'else 'comment_edit'end);
 if deleting is null or expected_version is null or expected_version<1 or(not deleting and(requested_text is null
 or char_length(requested_text)not between 1 and 200 or requested_text!~'[^[:space:]]'))then
 raise exception using errcode='22023',message='invalid_comment';end if;
 perform private.lock_recommendation_user(auth.uid());
 result:=private.replay_recommendation_action(auth.uid(),requested_id,fingerprint);if result is not null then return result;end if;
 select post.* into p from feed.comments subject join feed.posts post on post.id=subject.post_id where subject.id=requested_comment for share of post;
 if not found or not private.feed_post_accessible(auth.uid(),p)then raise exception using errcode='PT404',message='comment_not_found';end if;
 select * into c from feed.comments where id=requested_comment and author_id=auth.uid()for update;
 if not found then raise exception using errcode='PT404',message='comment_not_found';end if;
 if c.version<>expected_version then raise exception using errcode='PT409',message='comment_version_conflict';end if;
 if not deleting and(c.deleted_at is not null or c.moderation_status<>'allowed')then raise exception using errcode='22023',message='comment_unavailable';end if;
 if deleting and c.deleted_at is null then
  update feed.comments set text='',deleted_at=statement_timestamp(),updated_at=statement_timestamp(),version=version+1 where id=c.id returning * into c;
 elsif not deleting and c.text<>requested_text then
  update feed.comments set text=requested_text,version=version+1,updated_at=statement_timestamp()where id=c.id returning * into c;
 end if;
 result:=jsonb_build_object('id',c.id,'version',c.version,'deleted',c.deleted_at is not null,'request_id',requested_id,'replayed',false);
 insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,fingerprint,result);
 return result;
end $$;
create function private.set_feed_comment_liked_impl(requested_id uuid,requested_comment uuid,requested_liked boolean,expected_version bigint,
 expected_comment_version integer,expected_post_version integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare c feed.comments%rowtype;p feed.posts%rowtype;s recsys.user_states%rowtype;av bigint;changed integer;result jsonb;
 fingerprint jsonb:=jsonb_build_array('comment_like',requested_comment,requested_liked,expected_version,expected_comment_version,expected_post_version);
begin
 perform private.require_social_account();perform private.consume_social_quota('comment_action');
 if requested_liked is null or expected_version is null or expected_version<0 or expected_comment_version is null or expected_post_version is null then
 raise exception using errcode='22023',message='invalid_comment_action';end if;
 s:=private.lock_recommendation_user(auth.uid());
 result:=private.replay_recommendation_action(auth.uid(),requested_id,fingerprint);if result is not null then return result;end if;
 select post.* into p from feed.comments subject join feed.posts post on post.id=subject.post_id where subject.id=requested_comment for share of post;
 if not found or not private.feed_post_accessible(auth.uid(),p)then raise exception using errcode='PT404',message='comment_not_found';end if;
 select * into c from feed.comments where id=requested_comment for share;
 if not found or not private.feed_comment_body_allowed(auth.uid(),c)then raise exception using errcode='PT404',message='comment_not_found';end if;
 if c.version<>expected_comment_version or p.version<>expected_post_version then raise exception using errcode='PT409',message='comment_content_changed';end if;
 select coalesce((select version from feed.comment_action_versions where user_id=auth.uid()and comment_id=c.id),0)into av;
 if av<>expected_version then raise exception using errcode='PT409',message='comment_action_version_conflict';end if;
 insert into feed.comment_action_versions as v(user_id,comment_id,version)values(auth.uid(),c.id,1)
 on conflict(user_id,comment_id)do update set version=v.version+1 returning version into av;
 if requested_liked then
  insert into feed.comment_likes(user_id,comment_id,comment_version,post_version,epoch)values(auth.uid(),c.id,c.version,c.post_version,s.epoch)on conflict do nothing;
 else delete from feed.comment_likes where user_id=auth.uid()and comment_id=c.id;end if;
 get diagnostics changed=row_count;
 result:=jsonb_build_object('id',c.id,'request_id',requested_id,'action_version',av,'liked',requested_liked,'changed',changed>0,'replayed',false);
 insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,fingerprint,result);return result;
end $$;

-- Freeze issued page IDs, not an unbounded copy of every thread per reader.
-- Remaining roots are chosen by current popularity with a persistent exclusion
-- ledger: likes cannot duplicate/skip a root across pages. Replays keep IDs.
create function private.get_feed_comments_impl(requested_post uuid,requested_root uuid,requested_sort text,requested_session uuid,
 after_position integer,requested_limit integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;s feed.page_sessions%rowtype;page feed.page_metadata%rowtype;
 chosen uuid[];items jsonb;more boolean;target uuid;position integer;next_pos integer;
begin
 perform private.require_social_account();perform private.consume_social_quota('comment_read');
 if requested_sort is null or requested_sort not in('popular','old','new')or requested_limit is null or requested_limit not between 1 and 30
 or after_position is null or after_position< -1 or(requested_root is not null and requested_sort<>'old')then
 raise exception using errcode='22023',message='invalid_comment_cursor';end if;
 select * into p from feed.posts where id=requested_post;
 if not found or not private.feed_post_accessible(auth.uid(),p)then raise exception using errcode='PT404',message='post_not_found';end if;
 if requested_root is not null and not exists(select 1 from feed.comments where id=requested_root and root_id=id and post_id=p.id)then
 raise exception using errcode='PT404',message='thread_not_found';end if;
 -- Serializes only session allocation for this reader, never all readers.
 perform pg_advisory_xact_lock(hashtextextended('comment-pages:'||auth.uid()::text,0));
 if requested_session is null then
  if after_position<> -1 then raise exception using errcode='22023',message='invalid_comment_cursor';end if;
  if(select count(*)from feed.page_sessions where user_id=auth.uid()and expires_at>statement_timestamp())>=128 then
   raise exception using errcode='42901',message='comment_sessions_rate_limited';end if;
  insert into feed.page_sessions(id,user_id,post_id,root_id,sort,page_size)
  values(extensions.gen_random_uuid(),auth.uid(),p.id,requested_root,requested_sort,requested_limit)returning * into s;
 else
  select * into s from feed.page_sessions where id=requested_session and user_id=auth.uid()for update;
  if not found then raise exception using errcode='PT404',message='comment_session_not_found';end if;
  if s.post_id<>requested_post or s.root_id is distinct from requested_root or s.sort<>requested_sort or s.page_size<>requested_limit then
   raise exception using errcode='22023',message='comment_cursor_context_mismatch';end if;
  if s.expires_at<=statement_timestamp()then raise exception using errcode='PT410',message='comment_session_expired';end if;
 end if;
 select * into page from feed.page_metadata where session_id=s.id and page_metadata.after_position=get_feed_comments_impl.after_position;
 if not found then
  if after_position<>s.next_position-1 then raise exception using errcode='22023',message='invalid_comment_cursor';end if;
  if s.next_position>0 and exists(select 1 from feed.page_metadata where session_id=s.id and not has_more)then
   raise exception using errcode='22023',message='comment_page_exhausted';end if;
  if requested_root is null then
   -- Materialize the cheap ordered exclusion first. Visibility functions then
   -- run only until this page is full, including on deeply paginated threads.
   if requested_sort='popular'then
    with unseen as materialized(
     select c,st.likes,st.replies from feed.comment_statistics st join feed.comments c on c.id=st.comment_id
     where st.post_id=p.id and st.is_root and c.created_at<=s.created_at
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.comment_id=c.id)
     order by st.likes desc,st.created_at desc,st.comment_id)
    select array_agg(id order by likes desc,created_at desc,id)into chosen from(
     select (c).id,(c).created_at,likes from unseen
     where private.feed_comment_body_allowed(auth.uid(),c)or replies>0 limit requested_limit+1)q;
   elsif requested_sort='old'then
    with unseen as materialized(
     select c,st.replies from feed.comments c join feed.comment_statistics st on st.comment_id=c.id
     where c.post_id=p.id and c.root_id=c.id and c.created_at<=s.created_at
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.comment_id=c.id)
     order by c.created_at,c.id)
    select array_agg(id order by created_at,id)into chosen from(
     select (c).id,(c).created_at from unseen
     where private.feed_comment_body_allowed(auth.uid(),c)or replies>0 limit requested_limit+1)q;
   else
    with unseen as materialized(
     select c,st.replies from feed.comments c join feed.comment_statistics st on st.comment_id=c.id
     where c.post_id=p.id and c.root_id=c.id and c.created_at<=s.created_at
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.comment_id=c.id)
     order by c.created_at desc,c.id)
    select array_agg(id order by created_at desc,id)into chosen from(
     select (c).id,(c).created_at from unseen
     where private.feed_comment_body_allowed(auth.uid(),c)or replies>0 limit requested_limit+1)q;
   end if;
  else
   select array_agg(id order by created_at,id)into chosen from(select c.id,c.created_at from feed.comments c
    where c.root_id=requested_root and c.id<>c.root_id and c.created_at<=s.created_at
    and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.comment_id=c.id)
    order by c.created_at,c.id limit requested_limit+1)q;
  end if;
  chosen:=coalesce(chosen,'{}');more:=cardinality(chosen)>requested_limit;chosen:=chosen[1:requested_limit];
  insert into feed.page_items(session_id,position,comment_id)
  select s.id,s.next_position+ordinality-1,id from unnest(chosen)with ordinality ids(id,ordinality);
  next_pos:=s.next_position+coalesce(cardinality(chosen),0);
  update feed.page_sessions set next_position=next_pos where id=s.id;
  insert into feed.page_metadata(session_id,after_position,last_position,has_more)values(s.id,after_position,next_pos-1,more)returning * into page;
 end if;
 select coalesce(jsonb_agg(c.body order by i.position),'[]')into items from feed.page_items i
 join lateral private.feed_comment_rows(auth.uid(),array(select comment_id from feed.page_items where session_id=s.id
 and page_items.position>page.after_position and page_items.position<=page.last_position))c on c.id=i.comment_id
 where i.session_id=s.id and i.position>page.after_position and i.position<=page.last_position;
 return jsonb_build_object('session_id',s.id,'expires_at',s.expires_at,'post_id',p.id,'root_id',requested_root,'sort',s.sort,'items',items,
 'has_more',page.has_more,'next_cursor',case when page.has_more then jsonb_build_object('session_id',s.id,'after_position',page.last_position)else null end);
end $$;

create function private.capture_feed_repost()
returns trigger language plpgsql security definer set search_path=''as $$
declare r feed.reposts%rowtype;was_active boolean:=false;is_active boolean:=false;s recsys.user_states%rowtype;
begin
 if tg_op<>'INSERT'then was_active:=old.deleted_at is null and old.moderation_status='allowed';end if;
 if tg_op<>'DELETE'then is_active:=new.deleted_at is null and new.moderation_status='allowed';r:=new;else r:=old;end if;
 if was_active=is_active then return null;end if;
 if exists(select 1 from feed.posts where id=r.original_post_id)then
  insert into recsys.post_statistics as st(post_id,reposts)values(r.original_post_id,case when is_active then 1 else 0 end)
  on conflict(post_id)do update set reposts=greatest(0,st.reposts+case when is_active then 1 else -1 end);
 end if;
 if is_active and exists(select 1 from public.profiles where id=r.author_id)then
  s:=private.lock_recommendation_user(r.author_id);
  insert into recsys.social_feedback(user_id,post_id,post_version,epoch,kind,entity_id)
  values(r.author_id,r.original_post_id,r.original_version,s.epoch,'repost',r.id)on conflict do nothing;
 else delete from recsys.social_feedback where user_id=r.author_id and kind='repost'and entity_id=r.id;end if;
 return null;
end $$;
create trigger feed_repost_feedback after insert or delete or update of deleted_at,moderation_status on feed.reposts for each row execute function private.capture_feed_repost();
create function private.sync_quote_repost()
returns trigger language plpgsql security definer set search_path=''as $$
begin
 update feed.reposts set deleted_at=new.deleted_at,moderation_status=new.moderation_status where post_id=new.id;
 return null;
end $$;
create trigger feed_quote_state after update of deleted_at,moderation_status on feed.posts for each row execute function private.sync_quote_repost();
create function private.create_feed_repost_impl(requested_id uuid,requested_original uuid,requested_text text,requested_audience text,requested_language text)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;original feed.posts%rowtype;r feed.reposts%rowtype;depth integer:=0;
 fingerprint jsonb:=jsonb_build_array(requested_original,requested_text,requested_audience,requested_language);
begin
 perform private.require_social_account();perform private.consume_feed_quota('post_create_request');
 if requested_id is null or requested_original is null or requested_id=requested_original or requested_text is null or char_length(requested_text)>1000
 or(requested_text<>''and requested_text!~'[^[:space:]]')or requested_audience is null or requested_audience not in('public','friends')
 or requested_language is null or requested_language not in('ru','en')then raise exception using errcode='22023',message='invalid_repost';end if;
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
   insert into feed.posts(id,author_id,text,audience,language,creation_request,is_repost,original_post_id)
   values(requested_id,auth.uid(),requested_text,requested_audience,requested_language,fingerprint,true,original.id);
  end if;
  insert into feed.reposts(id,author_id,original_post_id,original_version,post_id,audience,creation_request)
  values(requested_id,auth.uid(),original.id,original.version,case when requested_text<>''then requested_id else null end,requested_audience,fingerprint)returning * into r;
 end if;
 select * into original from feed.posts where id=r.original_post_id;
 if not private.feed_post_accessible(auth.uid(),original)then raise exception using errcode='PT404',message='post_not_found';end if;
 return jsonb_build_object('id',r.id,'post_id',r.post_id,'original_post_id',r.original_post_id,'version',r.version,'created_at',r.created_at,'is_quote',r.post_id is not null);
end $$;
create function private.delete_feed_repost_impl(requested_id uuid,requested_repost uuid,expected_version integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare r feed.reposts%rowtype;result jsonb;fingerprint jsonb:=jsonb_build_array('delete_repost',requested_repost,expected_version);
begin
 perform private.require_social_account();perform private.consume_feed_quota('post_delete_request');
 if expected_version is null or expected_version<1 then raise exception using errcode='22023',message='invalid_repost_version';end if;
 perform private.lock_recommendation_user(auth.uid());
 result:=private.replay_recommendation_action(auth.uid(),requested_id,fingerprint);if result is not null then return result;end if;
 -- Quote deletion acquires post before repost, like the post-state trigger.
 perform p.id from feed.posts p join feed.reposts rep on rep.post_id=p.id where rep.id=requested_repost and rep.author_id=auth.uid()for update of p;
 select * into r from feed.reposts where id=requested_repost and author_id=auth.uid()for update;
 if not found then raise exception using errcode='PT404',message='repost_not_found';end if;
 if r.version<>expected_version then raise exception using errcode='PT409',message='repost_version_conflict';end if;
 if r.deleted_at is null then
  perform private.consume_feed_quota('post_delete');
  if r.post_id is not null then update feed.posts set deleted_at=statement_timestamp(),updated_at=statement_timestamp(),version=version+1 where id=r.post_id;end if;
  update feed.reposts set deleted_at=coalesce(deleted_at,statement_timestamp()),version=version+1 where id=r.id returning * into r;
 end if;
 result:=jsonb_build_object('id',r.id,'version',r.version,'deleted',true,'replayed',false,'request_id',requested_id);
 insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,fingerprint,result);return result;
end $$;

create function private.submit_feed_content_report_impl(requested_id uuid,requested_type text,requested_content uuid,requested_reason text)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;c feed.comments%rowtype;target uuid;snapshot jsonb;result jsonb;created timestamptz;
 fingerprint jsonb:=jsonb_build_array('content_report',requested_type,requested_content,requested_reason);
begin
 perform private.require_social_account();perform private.consume_social_quota('report_request');
 if requested_type is null or requested_type not in('post','comment')or requested_content is null or requested_reason is null
 or requested_reason not in('spam','scam','pornography','other')then raise exception using errcode='22023',message='invalid_content_report';end if;
 perform private.lock_recommendation_user(auth.uid());
 result:=private.replay_recommendation_action(auth.uid(),requested_id,fingerprint);if result is not null then return result;end if;
 if requested_type='post'then
  select * into p from feed.posts where id=requested_content for share;
 else
  select post.* into p from feed.comments subject join feed.posts post on post.id=subject.post_id where subject.id=requested_content for share of post;
 end if;
 if p.id is null or not private.feed_post_accessible(auth.uid(),p)then raise exception using errcode='PT404',message='report_target_not_found';end if;
 if requested_type='post'then
  target:=p.author_id;snapshot:=jsonb_build_object('post_id',p.id,'version',p.version,'text',p.text,'author_id',p.author_id,
    'original_post_id',p.original_post_id,'photo_count',p.photo_count);
 else
  select * into c from feed.comments where id=requested_content for share;
  if not found or not private.feed_comment_body_allowed(auth.uid(),c)then raise exception using errcode='PT404',message='report_target_not_found';end if;
  target:=c.author_id;snapshot:=jsonb_build_object('comment_id',c.id,'post_id',c.post_id,'root_id',c.root_id,'version',c.version,'text',c.text,'author_id',c.author_id);
 end if;
 if target=auth.uid()then raise exception using errcode='22023',message='invalid_report_target';end if;
 if exists(select 1 from private.user_reports where reporter_user_id=auth.uid()and target_type=requested_type and content_id=requested_content
  and created_at>statement_timestamp()-interval '7 days')then raise exception using errcode='42901',message='content_report_target_rate_limited';end if;
 perform private.consume_social_quota('report_'||requested_type);
 insert into private.user_reports(reporter_user_id,target_user_id,reason,target_type,content_id,content_snapshot)
 values(auth.uid(),target,requested_reason,requested_type,requested_content,snapshot)returning created_at into created;
 insert into feed.reported_content_hides(user_id,target_type,target_id)values(auth.uid(),requested_type,requested_content)on conflict do nothing;
 update recsys.user_states set revision=revision+1 where user_id=auth.uid();
 perform private.queue_recommendation_refresh(auth.uid(),(select revision from recsys.user_states where user_id=auth.uid()));
 result:=jsonb_build_object('request_id',requested_id,'target_type',requested_type,'target_id',requested_content,'created_at',created,'replayed',false);
 insert into recsys.action_requests(user_id,id,payload,response)values(auth.uid(),requested_id,fingerprint,result);return result;
end $$;

create function private.get_friends_feed_impl(requested_session uuid,after_position integer,requested_limit integer)
returns jsonb language plpgsql security definer set search_path=''as $$
declare s feed.page_sessions%rowtype;page feed.page_metadata%rowtype;state recsys.user_states%rowtype;
 chosen uuid[];items jsonb;more boolean;cursor integer;target uuid;current_post feed.posts%rowtype;delivery uuid;expires timestamptz;
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
 select * into page from feed.page_metadata where session_id=s.id and page_metadata.after_position=get_friends_feed_impl.after_position;
 if not found then
  if after_position<>s.next_position-1 then raise exception using errcode='22023',message='invalid_friends_cursor';end if;
  with friends as materialized(select case when user_one_id=auth.uid()then user_two_id else user_one_id end id
   from public.friendships where user_one_id=auth.uid()or user_two_id=auth.uid()),
  events as(
   select found.id,found.at from friends f cross join lateral(
    with unseen as materialized(
     select p from feed.posts p where p.author_id=f.id and p.created_at<=s.created_at
     and p.deleted_at is null and p.moderation_status='allowed'
     and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
     order by p.created_at desc,p.id)
    select (p).id,(p).created_at at from unseen
    where private.feed_post_accessible(auth.uid(),p)limit requested_limit+1)found
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
   select p.id,r.at from recent r join feed.posts p on p.id=r.id where private.feed_post_accessible(auth.uid(),p)
   and not exists(select 1 from feed.page_items i where i.session_id=s.id and i.post_id=p.id)
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
 with friends as materialized(select case when user_one_id=auth.uid()then user_two_id else user_one_id end id
   from public.friendships where user_one_id=auth.uid()or user_two_id=auth.uid())
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


create or replace function private.base_feed_post_json(p feed.posts)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',p.id,'author_id',p.author_id,'text',p.text,'audience',p.audience,'language',p.language,
    'version',p.version,'created_at',p.created_at,'updated_at',p.updated_at,'location',private.feed_post_location(p),
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'bucket','feed-media','path',u.image_path,
      'thumbnail_path',u.thumbnail_path,'width',u.width,'height',u.height,'bytes',u.image_bytes,'sha256',u.sha256,'mime','image/jpeg')order by u.position)
      from feed.photo_uploads u where u.draft_id=p.id and u.state='attached'),'[]'::jsonb));
$$;

create function private.feed_post_json_depth(p feed.posts,depth integer)
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
 and exists(select 1 from public.friendships f where f.user_one_id=least(auth.uid(),r.author_id)and f.user_two_id=greatest(auth.uid(),r.author_id))and private.feed_post_visible(auth.uid(),r.author_id,r.audience)
 order by r.created_at desc,r.id limit 3)chosen;
 return result||jsonb_build_object('is_repost',p.is_repost,'reposted_by',context,
 'my_repost',(select jsonb_build_object('id',r.id,'version',r.version)from feed.reposts r where r.author_id=auth.uid()and r.original_post_id=p.id and r.post_id is null and r.deleted_at is null and r.moderation_status='allowed'),
 'comment_count',coalesce((select comment_count from recsys.post_statistics where post_id=p.id),0),
 'repost_count',coalesce((select reposts from recsys.post_statistics where post_id=p.id),0));
end $$;
create or replace function private.feed_post_json(p feed.posts)
returns jsonb language sql stable security definer set search_path=''as $$select private.feed_post_json_depth(p,0);$$;

create or replace function private.get_feed_post_impl(requested_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p feed.posts%rowtype; s recsys.user_states%rowtype; delivery uuid; delivery_until timestamptz;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('post_read');
  s:=private.lock_recommendation_user(auth.uid());
  select * into p from feed.posts subject where id=requested_id and deleted_at is null and moderation_status='allowed'
    and private.feed_post_accessible(auth.uid(),subject);
  if not found then return null; end if;
  insert into recsys.deliveries(user_id,post_id,post_version,epoch,surface,model,embedding_model)
    values(auth.uid(),p.id,p.version,s.epoch,'direct','direct-v1',
      'intfloat/multilingual-e5-small@614241f622f53c4eeff9890bdc4f31cfecc418b3:onnx-int8:query') returning id,valid_until into delivery,delivery_until;
  return private.feed_post_json(p)||jsonb_build_object('delivery_id',delivery,'delivery_expires_at',delivery_until,'action_version',
    coalesce((select version from recsys.post_action_versions where user_id=auth.uid()and post_id=p.id),0),
    'liked',exists(select 1 from feed.post_likes where user_id=auth.uid()and post_id=p.id),
    'less_similar',exists(select 1 from recsys.semantic_suppressions where user_id=auth.uid()and post_id=p.id));
end $$;

create or replace function private.apply_feed_action_impl(requested_id uuid, requested_delivery uuid, requested_action text, expected_version bigint)
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
  select * into p from feed.posts subject where id=d.post_id and version=d.post_version
    and deleted_at is null and moderation_status='allowed' and private.feed_post_accessible(auth.uid(),subject) for share;
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

create or replace function private.record_feed_events_impl(requested_events jsonb)
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

create or replace function recsys.publish_recommendations(viewer uuid, requested_lease uuid, requested_result jsonb)
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
      or not private.feed_post_accessible(viewer,p)) then
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

create or replace function private.feed_media_read_allowed(object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles where id=auth.uid())
    and not private.is_account_globally_banned(auth.uid())and not private.is_account_pending_deletion(auth.uid())
    and exists(select 1 from feed.photo_uploads u join feed.posts p on p.id=u.draft_id
    where(object_path=u.image_path or object_path=u.thumbnail_path)and u.state='attached'
      and p.deleted_at is null and p.moderation_status='allowed'and private.feed_post_accessible(auth.uid(),p));
$$;

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
      and created_at>statement_timestamp()-interval '1 hour'
      union all select 1 from feed.reposts where author_id=viewer and post_id is null and created_at>statement_timestamp()-interval '1 hour' limit 12) recent;
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

create or replace function private.delete_feed_post_impl(requested_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare p feed.posts%rowtype;
begin
  perform private.require_active_account();
  perform private.consume_feed_quota('post_delete_request');
  perform private.lock_recommendation_user(auth.uid());
  select * into p from feed.posts where id = requested_id and author_id = auth.uid() for update;
  if not found then raise exception using errcode = 'P0002', message = 'post_not_found'; end if;
  if p.deleted_at is not null then return; end if;
  perform private.consume_feed_quota('post_delete');
  update feed.posts set deleted_at = statement_timestamp() where id = p.id;
end $$;

create or replace function private.submit_user_report_impl(
  p_target_user_id uuid,
  p_report_reason text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  report_created_at timestamptz;
  today_utc date := (now() at time zone 'UTC')::date;
  current_day_count integer;
begin
  perform private.require_active_account();
  if p_target_user_id is null or p_target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_report_target';
  end if;
  if p_report_reason not in ('spam', 'scam', 'pornography', 'other') then
    raise exception using errcode = '22023', message = 'invalid_report_reason';
  end if;
  if not exists (select 1 from public.profiles where id = p_target_user_id) then
    raise exception using errcode = 'P0002', message = 'report_target_not_found';
  end if;

  -- One advisory lock serializes all of a reporter's quota checks, including
  -- simultaneous attempts against different targets.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_user_id::text, 92173)
  );
  if exists (
    select 1
    from private.user_reports report
    where report.target_type='user' and report.reporter_user_id = current_user_id
      and report.target_user_id = p_target_user_id
      and report.created_at > now() - interval '7 days'
  ) then
    raise exception using errcode = 'P0001', message = 'user_report_target_rate_limited';
  end if;

  insert into private.user_report_daily_limits as limit_row (
    reporter_user_id, day_utc, distinct_target_count
  ) values (current_user_id, today_utc, 0)
  on conflict (reporter_user_id, day_utc) do nothing;

  select limit_row.distinct_target_count
  into current_day_count
  from private.user_report_daily_limits limit_row
  where limit_row.reporter_user_id = current_user_id
    and limit_row.day_utc = today_utc
  for update;

  if current_day_count >= 5 then
    raise exception using errcode = 'P0001', message = 'user_report_daily_rate_limited';
  end if;

  insert into private.user_reports (
    reporter_user_id, target_user_id, reason
  ) values (
    current_user_id, p_target_user_id, p_report_reason
  ) returning created_at into report_created_at;

  update private.user_report_daily_limits limit_row
  set distinct_target_count = limit_row.distinct_target_count + 1
  where limit_row.reporter_user_id = current_user_id
    and limit_row.day_utc = today_utc;

  return report_created_at;
end;
$$;

create or replace view private.moderation_user_reports as
select
  report.id,
  report.created_at,
  report.reason,
  report.reporter_user_id,
  reporter.username as reporter_username,
  reporter.display_name as reporter_display_name,
  report.target_user_id,
  target.username as target_username,
  target.display_name as target_display_name,
  count(*) filter(where report.target_type='user')over (partition by report.target_user_id)::integer as target_report_count,
  count(*) filter(where report.target_type='user')over (partition by report.reporter_user_id)::integer as reporter_report_count,
  (
    select count(*)::integer
    from public.user_blocks block
    where block.blocked_user_id = report.target_user_id
  ) as target_personal_block_count,
  (
    select count(*)::integer
    from private.global_account_bans ban
    where ban.target_user_id = report.target_user_id
  ) as target_global_ban_count,
  report.target_type,report.content_id,report.content_snapshot,
  case when report.target_type='user'then null else count(*)over(partition by report.target_type,report.content_id)::integer end as content_report_count
from private.user_reports report
join public.profiles reporter on reporter.id = report.reporter_user_id
join public.profiles target on target.id = report.target_user_id;

create function private.social_feedback_allowed(viewer uuid,f recsys.social_feedback)
returns boolean language sql stable security definer set search_path=''as $$
 select case f.kind when 'repost'then exists(select 1 from feed.reposts r where r.id=f.entity_id and r.author_id=viewer
 and r.deleted_at is null and r.moderation_status='allowed')
 when 'comment'then exists(select 1 from feed.comments c where c.id=f.entity_id and private.feed_comment_body_allowed(viewer,c))
 else exists(select 1 from feed.comments c join feed.comment_likes l on l.comment_id=c.id and l.user_id=viewer
 where c.id=f.entity_id and l.comment_version=c.version and private.feed_comment_body_allowed(viewer,c))end;
$$;

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
      (exists(select 1 from social where author_id=p.author_id)or exists(select 1 from affinity where author_id=p.author_id)or 'friends_repost'=any(ids.sources)) social,coalesce(st.impressions,0)impressions,
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
  -- Acquire user -> job locks like all foreground paths. Never wait behind a
  -- currently active user just to remove an obsolete refresh request.
  with inactive as(select s.user_id from recsys.user_states s where s.active_until<statement_timestamp()
    and exists(select 1 from recsys.refresh_jobs j where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp()))
    order by s.active_until,s.user_id for update skip locked limit 100)
  delete from recsys.refresh_jobs j using inactive s where j.user_id=s.user_id and(j.locked_until is null or j.locked_until<statement_timestamp());
  get diagnostics affected=row_count;return removed+affected;
end $$;

create function public.create_feed_comment(requested_id uuid,requested_post uuid,requested_text text,requested_reply_to uuid default null)
returns jsonb language sql security invoker set search_path=''as $$select private.create_feed_comment_impl(requested_id,requested_post,requested_text,requested_reply_to);$$;
create function public.edit_feed_comment(requested_id uuid,requested_comment uuid,expected_version integer,requested_text text)
returns jsonb language sql security invoker set search_path=''as $$select private.mutate_feed_comment_impl(requested_id,requested_comment,expected_version,requested_text,false);$$;
create function public.delete_feed_comment(requested_id uuid,requested_comment uuid,expected_version integer)
returns jsonb language sql security invoker set search_path=''as $$select private.mutate_feed_comment_impl(requested_id,requested_comment,expected_version,null,true);$$;
create function public.set_feed_comment_liked(requested_id uuid,requested_comment uuid,requested_liked boolean,expected_version bigint,
 expected_comment_version integer,expected_post_version integer)
returns jsonb language sql security invoker set search_path=''as $$select private.set_feed_comment_liked_impl(requested_id,requested_comment,requested_liked,expected_version,expected_comment_version,expected_post_version);$$;
create function public.get_feed_comments(requested_post uuid,requested_root uuid default null,requested_sort text default 'popular',requested_session uuid default null,
 after_position integer default -1,requested_limit integer default 20)
returns jsonb language sql security invoker set search_path=''as $$select private.get_feed_comments_impl(requested_post,requested_root,requested_sort,requested_session,after_position,requested_limit);$$;
create function public.get_feed_comment_replies(requested_post uuid,requested_root uuid,requested_session uuid default null,after_position integer default -1,requested_limit integer default 20)
returns jsonb language sql security invoker set search_path=''as $$select private.get_feed_comments_impl(requested_post,requested_root,'old',requested_session,after_position,requested_limit);$$;
create function public.create_feed_repost(requested_id uuid,requested_original uuid,requested_text text default '',requested_audience text default 'public',requested_language text default 'ru')
returns jsonb language sql security invoker set search_path=''as $$select private.create_feed_repost_impl(requested_id,requested_original,requested_text,requested_audience,requested_language);$$;
create function public.delete_feed_repost(requested_id uuid,requested_repost uuid,expected_version integer)
returns jsonb language sql security invoker set search_path=''as $$select private.delete_feed_repost_impl(requested_id,requested_repost,expected_version);$$;
create function public.submit_feed_content_report(requested_id uuid,requested_type text,requested_content uuid,requested_reason text)
returns jsonb language sql security invoker set search_path=''as $$select private.submit_feed_content_report_impl(requested_id,requested_type,requested_content,requested_reason);$$;
create function public.get_friends_feed(requested_session uuid default null,after_position integer default -1,requested_limit integer default 20)
returns jsonb language sql security invoker set search_path=''as $$select private.get_friends_feed_impl(requested_session,after_position,requested_limit);$$;

do $$declare name text;begin
 foreach name in array array['reposts','comments','comment_statistics','comment_likes','comment_action_versions','page_sessions','page_items','page_metadata','reported_content_hides']loop
 execute 'alter table feed.'||name||' enable row level security';
 execute 'revoke all on feed.'||name||' from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker';
 end loop;
 alter table recsys.social_feedback enable row level security;
 alter table private.feed_social_limits enable row level security;
 revoke all on recsys.social_feedback,private.feed_social_limits from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
end $$;

revoke all on function private.require_social_account() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.consume_social_quota(text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.feed_post_accessible(uuid,feed.posts,boolean) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.semantic_feed_post(uuid) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.feed_social_feedback_change() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.capture_feed_comment() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.anonymize_feed_comment() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.capture_feed_comment_like() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.feed_comment_body_allowed(uuid,feed.comments) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.feed_comment_rows(uuid,uuid[]) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.create_feed_comment_impl(uuid,uuid,text,uuid) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.create_feed_comment_impl(uuid,uuid,text,uuid) to authenticated;
revoke all on function private.mutate_feed_comment_impl(uuid,uuid,integer,text,boolean) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.mutate_feed_comment_impl(uuid,uuid,integer,text,boolean) to authenticated;
revoke all on function private.set_feed_comment_liked_impl(uuid,uuid,boolean,bigint,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.set_feed_comment_liked_impl(uuid,uuid,boolean,bigint,integer,integer) to authenticated;
revoke all on function private.get_feed_comments_impl(uuid,uuid,text,uuid,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.get_feed_comments_impl(uuid,uuid,text,uuid,integer,integer) to authenticated;
revoke all on function private.capture_feed_repost() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.sync_quote_repost() from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.create_feed_repost_impl(uuid,uuid,text,text,text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.create_feed_repost_impl(uuid,uuid,text,text,text) to authenticated;
revoke all on function private.delete_feed_repost_impl(uuid,uuid,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.delete_feed_repost_impl(uuid,uuid,integer) to authenticated;
revoke all on function private.submit_feed_content_report_impl(uuid,text,uuid,text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.submit_feed_content_report_impl(uuid,text,uuid,text) to authenticated;
revoke all on function private.get_friends_feed_impl(uuid,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function private.get_friends_feed_impl(uuid,integer,integer) to authenticated;
revoke all on function private.feed_post_json_depth(feed.posts,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function private.social_feedback_allowed(uuid,recsys.social_feedback) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
revoke all on function public.create_feed_comment(uuid,uuid,text,uuid) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.create_feed_comment(uuid,uuid,text,uuid) to authenticated;
revoke all on function public.edit_feed_comment(uuid,uuid,integer,text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.edit_feed_comment(uuid,uuid,integer,text) to authenticated;
revoke all on function public.delete_feed_comment(uuid,uuid,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.delete_feed_comment(uuid,uuid,integer) to authenticated;
revoke all on function public.set_feed_comment_liked(uuid,uuid,boolean,bigint,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.set_feed_comment_liked(uuid,uuid,boolean,bigint,integer,integer) to authenticated;
revoke all on function public.get_feed_comments(uuid,uuid,text,uuid,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.get_feed_comments(uuid,uuid,text,uuid,integer,integer) to authenticated;
revoke all on function public.get_feed_comment_replies(uuid,uuid,uuid,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.get_feed_comment_replies(uuid,uuid,uuid,integer,integer) to authenticated;
revoke all on function public.create_feed_repost(uuid,uuid,text,text,text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.create_feed_repost(uuid,uuid,text,text,text) to authenticated;
revoke all on function public.delete_feed_repost(uuid,uuid,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.delete_feed_repost(uuid,uuid,integer) to authenticated;
revoke all on function public.submit_feed_content_report(uuid,text,uuid,text) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.submit_feed_content_report(uuid,text,uuid,text) to authenticated;
revoke all on function public.get_friends_feed(uuid,integer,integer) from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
grant execute on function public.get_friends_feed(uuid,integer,integer) to authenticated;
revoke all on function private.base_feed_post_json(feed.posts)from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
notify pgrst,'reload schema';

create index feed_reported_hides_target_idx on feed.reported_content_hides(target_type,target_id,user_id);
create function private.cleanup_feed_report_hides()
returns trigger language plpgsql security definer set search_path=''as $$
begin
 delete from feed.reported_content_hides where target_type=case when tg_table_name='posts'then 'post'else 'comment'end and target_id=old.id;
 return null;
end $$;
revoke all on function private.cleanup_feed_report_hides()from public,anon,authenticated,yap_recommendation_worker,yap_feed_media_worker;
create trigger feed_post_report_hides_cleanup after delete on feed.posts for each row execute function private.cleanup_feed_report_hides();
create trigger feed_comment_report_hides_cleanup after delete on feed.comments for each row execute function private.cleanup_feed_report_hides();

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
  if exists(select 1 from feed.reposts where id=requested_post)then raise exception using errcode='23505',message='post_id_conflict';end if;
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

notify pgrst,'reload schema';
