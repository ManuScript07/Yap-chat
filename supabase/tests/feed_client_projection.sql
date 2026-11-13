begin;

insert into auth.users(id, is_sso_user, is_anonymous, raw_user_meta_data)
select id, false, false, '{"name":"Feed client fixture"}'
from unnest(array[
  '70000000-0000-4000-8000-000000000001'::uuid,
  '70000000-0000-4000-8000-000000000002'::uuid,
  '70000000-0000-4000-8000-000000000003'::uuid
]) as id;

update public.profiles
set avatar_storage_path = id::text || '/feed-fixture.jpeg'
where id in ('70000000-0000-4000-8000-000000000001',
             '70000000-0000-4000-8000-000000000003');

do $$
declare
  author constant uuid := '70000000-0000-4000-8000-000000000001';
  viewer constant uuid := '70000000-0000-4000-8000-000000000002';
  replier constant uuid := '70000000-0000-4000-8000-000000000003';
  post constant uuid := '70000000-0000-4000-8000-000000000004';
  friends_post constant uuid := '70000000-0000-4000-8000-000000000005';
  root constant uuid := '70000000-0000-4000-8000-000000000006';
  reply constant uuid := '70000000-0000-4000-8000-000000000007';
  first_delivery uuid;
  second_delivery uuid;
  current_post jsonb;
  first_page jsonb;
  root_row jsonb;
  replies jsonb;
  event_payload jsonb;
  attempt jsonb;
  n integer;
begin
  perform set_config('request.jwt.claim.sub', author::text, true);
  set local role authenticated;
  perform public.publish_feed_post(post, 'Public post', 'public', 'en', '{}',
    '{"latitude":55.75,"longitude":37.62}');
  current_post := public.publish_feed_post(friends_post, 'For friends', 'friends',
    'en', '{}', '{"latitude":55.75,"longitude":37.62}');
  if (current_post #>> '{location,latitude}')::numeric is distinct from 55.75 then
    raise exception 'Author cannot see their publication location';
  end if;
  perform public.create_feed_comment(root, post, 'Root', null);
  reset role;

  perform set_config('request.jwt.claim.sub', replier::text, true);
  set local role authenticated;
  perform public.create_feed_comment(reply, post, 'First reply', root);
  reset role;

  perform set_config('request.jwt.claim.sub', viewer::text, true);
  set local role authenticated;
  perform public.set_feed_author_followed(extensions.gen_random_uuid(), author, true, 0);
  if public.get_feed_post(friends_post) is not null then
    raise exception 'A follow granted access to a friends-only post';
  end if;
  current_post := public.get_feed_post(post);
  if current_post #>> '{author,id}' is distinct from author::text
     or current_post #>> '{author,avatar_storage_path}' is distinct from author::text || '/feed-fixture.jpeg'
     or current_post #>> '{author,display_name}' is null
     or current_post #> '{location,latitude}' is not null
     or current_post -> 'edited' is distinct from 'false'::jsonb then
    raise exception 'Invalid public post presentation';
  end if;
  first_delivery := (current_post ->> 'delivery_id')::uuid;
  first_page := public.get_friends_feed(null, -1, 20);
  select (item ->> 'delivery_id')::uuid into second_delivery
  from jsonb_array_elements(first_page -> 'items') item
  where item #>> '{post,id}' = post::text and item #>> '{post,author,id}' = author::text;
  if second_delivery is null or second_delivery = first_delivery then
    raise exception 'Friends page did not expose a distinct delivery with the author projection';
  end if;
  attempt := public.apply_feed_action(extensions.gen_random_uuid(), first_delivery, 'like', 0);
  if attempt -> 'changed' is distinct from 'true'::jsonb then
    raise exception 'Initial like was not applied';
  end if;
  attempt := public.apply_feed_action(extensions.gen_random_uuid(), second_delivery, 'like', 1);
  if attempt -> 'changed' is distinct from 'false'::jsonb then
    raise exception 'A second delivery permitted a duplicate like';
  end if;
  event_payload := jsonb_build_object('event_id', extensions.gen_random_uuid(),
    'delivery_id', first_delivery, 'kind', 'impression', 'visible_ms', 1000, 'visible_fraction', 0.5);
  begin
    perform public.record_feed_events(jsonb_build_array(event_payload));
    raise exception 'An immediate impression was accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'unqualified_impression' then raise; end if;
  end;
  reset role;
  update recsys.deliveries set delivered_at = statement_timestamp() - interval '10 seconds'
  where id in (first_delivery, second_delivery);
  set local role authenticated;
  perform public.record_feed_events(jsonb_build_array(event_payload));
  attempt := public.record_feed_events(jsonb_build_array(event_payload));
  if attempt -> 'duplicates' is distinct from '1'::jsonb then
    raise exception 'Repeated impression UUID was not recognized';
  end if;
  perform public.record_feed_events(jsonb_build_array(event_payload || jsonb_build_object(
    'event_id', extensions.gen_random_uuid(), 'delivery_id', second_delivery)));
  current_post := public.get_feed_post(post);
  if current_post -> 'like_count' is distinct from '1'::jsonb
     or current_post -> 'view_count' is distinct from '1'::jsonb then
    raise exception 'Duplicate like or view in aggregate: %', current_post;
  end if;
  for n in 1..27 loop
    perform public.record_feed_events(jsonb_build_array(event_payload));
  end loop;
  begin
    perform public.record_feed_events(jsonb_build_array(event_payload));
    raise exception 'Impression batch quota was not enforced';
  exception when sqlstate '42901' then null;
  end;
  first_page := public.get_feed_comments(post, null, 'popular', null, -1, 20);
  select item into root_row from jsonb_array_elements(first_page -> 'items') item
  where item ->> 'id' = root::text;
  replies := public.get_feed_comment_replies(post, root, null, -1, 20);
  if root_row #>> '{author,id}' is distinct from author::text
     or root_row #>> '{reply_preview,id}' is distinct from reply::text
     or root_row #>> '{reply_preview,author,avatar_storage_path}' is distinct from replier::text || '/feed-fixture.jpeg'
     or root_row -> 'reply_preview' is distinct from replies #> '{items,0}' then
    raise exception 'Root preview disagrees with the chronological replies page';
  end if;
  attempt := public.set_feed_comment_liked(extensions.gen_random_uuid(), root, true, 0, 1, 1);
  attempt := public.set_feed_comment_liked(extensions.gen_random_uuid(), root, true, 1, 1, 1);
  if attempt -> 'changed' is distinct from 'false'::jsonb then
    raise exception 'Repeated comment like changed its aggregate: %', attempt;
  end if;
  select item into root_row from jsonb_array_elements(
    public.get_feed_comments(post, null, 'popular',
      (first_page ->> 'session_id')::uuid, -1, 20) -> 'items') item
  where item ->> 'id' = root::text;
  if root_row -> 'like_count' is distinct from '1'::jsonb then
    raise exception 'Repeated comment like changed the read counter';
  end if;
  perform public.submit_feed_content_report(extensions.gen_random_uuid(), 'comment', root, 'spam');
  select item into root_row from jsonb_array_elements(
    public.get_feed_comments(post, null, 'popular',
      (first_page ->> 'session_id')::uuid, -1, 20) -> 'items') item
  where item ->> 'id' = root::text;
  if root_row -> 'author' is distinct from 'null'::jsonb
     or root_row #>> '{reply_preview,id}' is distinct from reply::text
     or root_row #> '{reply_preview,reply_to}' is distinct from 'null'::jsonb then
    raise exception 'Preview exposed a reported root author or hid a visible reply';
  end if;
  reset role;

  insert into public.friendships(user_one_id, user_two_id) values (author, viewer);
  set local role authenticated;
  current_post := public.get_feed_post(friends_post);
  if (current_post #>> '{location,latitude}')::numeric is distinct from 55.75 then
    raise exception 'Mutual friend with precision permission did not see the location';
  end if;
  reset role;

  insert into public.user_blocks(blocker_user_id, blocked_user_id) values (viewer, replier);
  set local role authenticated;
  first_page := public.get_feed_comments(post, null, 'popular',
    (first_page ->> 'session_id')::uuid, -1, 20);
  select item into root_row from jsonb_array_elements(first_page -> 'items') item
  where item ->> 'id' = root::text;
  if root_row is null or root_row -> 'reply_preview' is distinct from 'null'::jsonb then
    raise exception 'A previously issued root page leaked the blocked reply';
  end if;
  reset role;
end;
$$;

rollback;
