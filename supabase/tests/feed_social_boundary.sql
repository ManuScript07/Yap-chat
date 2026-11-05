begin;

-- Raw social state stays private; only checked invoker RPCs are client-visible.
do $$
declare item record; role_name text; signature text;
begin
  for item in select c.oid,n.nspname,c.relname,c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where (n.nspname='feed' and c.relname in ('reposts','comments','comment_statistics',
      'comment_likes','comment_action_versions','page_sessions','page_items','page_metadata','reported_content_hides'))
      or (n.nspname='recsys' and c.relname='social_feedback')
      or (n.nspname='private' and c.relname='feed_social_limits')
  loop
    if not item.relrowsecurity then raise exception 'RLS missing on %.%',item.nspname,item.relname; end if;
    foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker'] loop
      if has_table_privilege(role_name,item.oid,'SELECT,INSERT,UPDATE,DELETE') then
        raise exception 'Raw social table grant to %: %.%',role_name,item.nspname,item.relname;
      end if;
    end loop;
  end loop;
  foreach signature in array array[
    'create_feed_comment(uuid,uuid,text,uuid)','edit_feed_comment(uuid,uuid,integer,text)',
    'delete_feed_comment(uuid,uuid,integer)','set_feed_comment_liked(uuid,uuid,boolean,bigint,integer,integer)',
    'get_feed_comments(uuid,uuid,text,uuid,integer,integer)','get_feed_comment_replies(uuid,uuid,uuid,integer,integer)',
    'create_feed_repost(uuid,uuid,text,text,text)','delete_feed_repost(uuid,uuid,integer)',
    'submit_feed_content_report(uuid,text,uuid,text)','get_friends_feed(uuid,integer,integer)']
  loop
    if not has_function_privilege('authenticated','public.'||signature,'EXECUTE') then
      raise exception 'Missing RPC grant: %',signature;
    end if;
    foreach role_name in array array['anon','yap_recommendation_worker','yap_feed_media_worker'] loop
      if has_function_privilege(role_name,'public.'||signature,'EXECUTE') then
        raise exception 'Unexpected RPC grant to %: %',role_name,signature;
      end if;
    end loop;
    if (select prosecdef from pg_proc where oid=('public.'||signature)::regprocedure) then
      raise exception 'Public definer wrapper: %',signature;
    end if;
  end loop;
  foreach signature in array array[
    'private.feed_post_accessible(uuid,feed.posts,boolean)',
    'private.feed_comment_rows(uuid,uuid[])','private.capture_feed_comment()',
    'private.capture_feed_comment_like()','private.capture_feed_repost()',
    'private.cleanup_feed_report_hides()','private.base_feed_post_json(feed.posts)',
    'private.feed_post_json_depth(feed.posts,integer)']
  loop
    foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker'] loop
      if has_function_privilege(role_name,signature,'EXECUTE') then
        raise exception 'Internal helper exposed to %: %',role_name,signature;
      end if;
    end loop;
  end loop;
  if has_table_privilege('authenticated','private.moderation_user_reports','SELECT') then
    raise exception 'Private moderation queue exposed';
  end if;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
  begin
    perform public.get_friends_feed();
    raise exception 'Missing identity accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
rollback;
