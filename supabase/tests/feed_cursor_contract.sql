begin;

insert into auth.users(id, is_sso_user, is_anonymous, raw_user_meta_data)
values ('76000000-0000-4000-8000-000000000001', false, false, '{"name":"Cursor author"}'),
       ('76000000-0000-4000-8000-000000000002', false, false, '{"name":"Cursor viewer"}');

do $$
declare
  author constant uuid := '76000000-0000-4000-8000-000000000001';
  viewer constant uuid := '76000000-0000-4000-8000-000000000002';
  post constant uuid := '76000000-0000-4000-8000-000000000003';
  root constant uuid := '76000000-0000-4000-8000-000000000004';
  reply constant uuid := '76000000-0000-4000-8000-000000000005';
  scroll constant uuid := '76000000-0000-4000-8000-000000000006';
  friends_page jsonb;
  nearby_page jsonb;
  comments jsonb;
  replies jsonb;
  personalized jsonb;
begin
  insert into public.friendships(user_one_id, user_two_id) values (author, viewer);
  insert into public.user_locations(user_id, latitude, longitude) values (viewer, 0, 0);
  perform set_config('request.jwt.claim.sub', author::text, true);
  set local role authenticated;
  perform public.publish_feed_post(post, 'cursor fixture', 'public', 'en', '{}', '{"latitude":0,"longitude":0}');
  perform public.create_feed_comment(root, post, 'root', null);
  perform public.create_feed_comment(reply, post, 'reply', root);
  reset role;
  -- The archive scan is bounded. Own posts fill its first scan window.
  update feed.posts set created_at = statement_timestamp() - interval '1 second'
  where id = post;
  insert into feed.posts(id, author_id, text, audience, language, creation_request, created_at)
  select extensions.gen_random_uuid(), viewer, 'own archive row', 'public', 'en', '[]',
    statement_timestamp() - interval '1 millisecond'
  from generate_series(1, 128);

  perform set_config('request.jwt.claim.sub', viewer::text, true);
  set local role authenticated;
  personalized := public.get_for_you_feed_v2(scroll, null, 2);
  if personalized->>'status' is distinct from 'continue'
    or personalized->'items' is distinct from '[]'::jsonb
    or personalized->>'next_cursor' is null then
    raise exception 'Empty personalized page lost its continuation';
  end if;
  personalized := public.get_for_you_feed_v2(scroll, (personalized->>'next_cursor')::uuid, 2);
  if jsonb_array_length(personalized->'items') = 0 then
    raise exception 'Personalized cursor did not advance past the empty window';
  end if;
  friends_page := public.get_friends_feed();
  nearby_page := public.get_nearby_feed();
  comments := public.get_feed_comments(post);
  replies := public.get_feed_comment_replies(post, root);
  if comments#>>'{items,0,reply_preview,id}' is distinct from reply::text
    or replies#>>'{items,0,id}' is distinct from reply::text
    or (replies#>'{items,0}') ? 'reply_preview' then
    raise exception 'Unexpected comment or reply shape';
  end if;
  reset role;

  update recsys.feed_scrolls set expires_at = statement_timestamp() - interval '1 second'
  where request_id = scroll;
  update feed.page_sessions set expires_at = statement_timestamp() - interval '1 second'
  where id in ((friends_page->>'session_id')::uuid, (nearby_page->>'session_id')::uuid,
    (comments->>'session_id')::uuid, (replies->>'session_id')::uuid);
  set local role authenticated;
  begin
    perform public.get_for_you_feed_v2(scroll);
    raise exception 'Expired personalized session accepted';
  exception when sqlstate 'PT410' then
    if sqlerrm <> 'feed_session_expired' then raise; end if;
  end;
  begin
    perform public.get_friends_feed((friends_page->>'session_id')::uuid);
    raise exception 'Expired friends session accepted';
  exception when sqlstate 'PT410' then
    if sqlerrm <> 'friends_session_expired' then raise; end if;
  end;
  begin
    perform public.get_nearby_feed((nearby_page->>'session_id')::uuid);
    raise exception 'Expired nearby session accepted';
  exception when sqlstate 'PT410' then
    if sqlerrm <> 'nearby_session_expired' then raise; end if;
  end;
  begin
    perform public.get_feed_comments(post, requested_session => (comments->>'session_id')::uuid);
    raise exception 'Expired comment session accepted';
  exception when sqlstate 'PT410' then
    if sqlerrm <> 'comment_session_expired' then raise; end if;
  end;
  begin
    perform public.get_feed_comment_replies(post, root, requested_session => (replies->>'session_id')::uuid);
    raise exception 'Expired reply session accepted';
  exception when sqlstate 'PT410' then
    if sqlerrm <> 'comment_session_expired' then raise; end if;
  end;
  reset role;

  update public.user_locations set updated_at = statement_timestamp() - interval '13 hours'
  where user_id = viewer;
  set local role authenticated;
  begin
    perform public.get_nearby_feed();
    raise exception 'Stale viewer location accepted';
  exception when sqlstate 'PT412' then
    if sqlerrm <> 'nearby_location_required' then raise; end if;
  end;
  reset role;
end $$;

rollback;
