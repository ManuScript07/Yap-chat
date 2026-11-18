-- Version the existing counter independently of post edits and reactions.
-- Existing totals start at revision zero. Only a count change advances it.
alter table recsys.post_statistics
  add column comment_count_revision bigint not null default 0;

create function private.bump_feed_comment_count_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.comment_count_revision := case when new.comment_count > 0 then 1 else 0 end;
  elsif new.comment_count is distinct from old.comment_count then
    new.comment_count_revision := old.comment_count_revision + 1;
  end if;
  return new;
end
$$;

revoke all on function private.bump_feed_comment_count_revision()
  from public, anon, authenticated, yap_recommendation_worker, yap_feed_media_worker;

create trigger feed_comment_count_revision
before insert or update of comment_count on recsys.post_statistics
for each row execute function private.bump_feed_comment_count_revision();
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
    'comment_count_revision', coalesce(st.comment_count_revision, 0),
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

create or replace function private.create_feed_comment_impl(requested_id uuid,requested_post uuid,requested_text text,requested_reply_to uuid)
returns jsonb language plpgsql security definer set search_path=''as $$
declare p feed.posts%rowtype;c feed.comments%rowtype;target feed.comments%rowtype;root uuid;result jsonb;
 total bigint; total_revision bigint;
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
 select body into result from private.feed_comment_rows(auth.uid(),array[c.id]);
 select st.comment_count, st.comment_count_revision into total, total_revision
 from recsys.post_statistics st where st.post_id = p.id;
 return result || jsonb_build_object(
   'post_comment_count', coalesce(total, 0),
   'post_comment_count_revision', coalesce(total_revision, 0)
 );
end $$;
