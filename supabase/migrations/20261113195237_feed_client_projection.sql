-- Add presentation fields to the existing checked read paths. Ranking,
-- pagination and write contracts continue to use their current implementations.
create or replace function private.base_feed_post_json(p feed.posts)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'author_id', p.author_id, 'text', p.text,
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

create or replace function private.feed_comment_rows(viewer uuid, ids uuid[])
returns table(id uuid, body jsonb) language sql stable security definer set search_path = '' as $$
  with chosen as materialized (
    select * from feed.comments where id = any(ids)
  ), previews as materialized (
    select root.id as root_id, preview.id as reply_id
    from chosen root
    join feed.comment_statistics stats on stats.comment_id = root.id and stats.replies > 0
    cross join lateral (
      -- Bound the work even when a thread starts with many unavailable replies.
      select candidate.id
      from (
        select c as comment, c.id, c.created_at from feed.comments c
        where c.root_id = root.id and c.id <> c.root_id
        order by c.created_at, c.id limit 8
      ) candidate
      where private.feed_comment_body_allowed(viewer, candidate.comment)
      order by candidate.created_at, candidate.id limit 1
    ) preview
    where root.id = root.root_id
  ), projected as materialized (
    select * from chosen
    union all
    select c.* from previews pr join feed.comments c on c.id = pr.reply_id
    where not (c.id = any(ids))
  ), identities as materialized (
    select author_id as id from projected
    union
    select target.author_id from projected c join feed.comments target on target.id = c.reply_to_id
  ), visible_users as materialized (
    select p.id, p.username, p.display_name, p.avatar_url, p.avatar_storage_path, p.avatar_updated_at
    from identities i join public.profiles p on p.id = i.id
    where not private.is_account_globally_banned(p.id)
      and not private.is_account_pending_deletion(p.id)
      and not private.is_user_pair_blocked_impl(viewer, p.id)
  ), rows as materialized (
    select c.*, p.version as current_post_version, u.id as visible_author,
      u.username, u.display_name, u.avatar_url, u.avatar_storage_path, u.avatar_updated_at,
      not (c.deleted_at is null and c.moderation_status = 'allowed'
        and u.id is not null and hidden.target_id is null) as unavailable,
      target.deleted_at as target_deleted, target.moderation_status as target_moderation,
      hidden_target.target_id is not null as target_reported,
      tu.id as target_user, tu.username as target_username,
      coalesce(st.likes, 0) as likes, coalesce(st.replies, 0) as replies,
      coalesce(v.version, 0) as action_version, l.comment_id is not null as liked
    from projected c
    join feed.posts p on p.id = c.post_id
    left join visible_users u on u.id = c.author_id
    left join feed.comments target on target.id = c.reply_to_id
    left join visible_users tu on tu.id = target.author_id
    left join feed.reported_content_hides hidden on hidden.user_id = viewer
      and hidden.target_type = 'comment' and hidden.target_id = c.id
    left join feed.reported_content_hides hidden_target on hidden_target.user_id = viewer
      and hidden_target.target_type = 'comment' and hidden_target.target_id = target.id
    left join feed.comment_statistics st on st.comment_id = c.id
    left join feed.comment_action_versions v on v.user_id = viewer and v.comment_id = c.id
    left join feed.comment_likes l on l.user_id = viewer and l.comment_id = c.id
  ), bodies as materialized (
    select c.id, jsonb_build_object(
      'id', c.id, 'post_id', c.post_id, 'root_id', c.root_id, 'version', c.version,
      'post_version', c.current_post_version, 'action_version', c.action_version,
      'text', case when c.unavailable then null else c.text end,
      'author', case when c.unavailable then null else jsonb_build_object(
        'id', c.visible_author, 'username', c.username, 'display_name', c.display_name,
        'avatar_url', c.avatar_url, 'avatar_storage_path', c.avatar_storage_path,
        'avatar_updated_at', c.avatar_updated_at) end,
      'state', case when c.deleted_at is not null then 'deleted'
                    when c.unavailable then 'unavailable' else 'active' end,
      'reply_to', case when c.unavailable or c.target_user is null or c.target_deleted is not null
        or c.target_moderation <> 'allowed' or c.target_reported then null else jsonb_build_object(
          'comment_id', c.reply_to_id, 'user_id', c.target_user, 'username', c.target_username) end,
      'created_at', c.created_at, 'updated_at', c.updated_at,
      'like_count', case when c.unavailable then 0 else c.likes end,
      'reply_count', c.replies, 'liked', case when c.unavailable then false else c.liked end
    ) as body from rows c
  )
  select c.id, case when c.id = c.root_id then b.body || jsonb_build_object('reply_preview', reply.body)
    else b.body end
  from chosen c join bodies b on b.id = c.id
  left join previews pr on pr.root_id = c.id
  left join bodies reply on reply.id = pr.reply_id;
$$;
