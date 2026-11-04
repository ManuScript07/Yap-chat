begin;

do $$ declare item record;role_name text;signature text;begin
  for item in select c.oid,n.nspname,c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where(n.nspname='feed'and c.relname in('post_drafts','photo_uploads'))or(n.nspname='media'and c.relname='cleanup_jobs')loop
    if not item.relrowsecurity then raise exception 'RLS missing on %.%',item.nspname,item.relname;end if;
    foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
      if has_table_privilege(role_name,item.oid,'SELECT,INSERT,UPDATE,DELETE')then raise exception 'Raw media table grant to %',role_name;end if;
    end loop;
  end loop;
  foreach signature in array array['reserve_feed_photo(uuid,uuid,integer,text)','confirm_feed_photo(uuid)',
    'get_feed_photo_status(uuid)','cancel_feed_draft(uuid)','publish_feed_post(uuid,text,text,text,uuid[],jsonb)']loop
    if not has_function_privilege('authenticated','public.'||signature,'EXECUTE')
      or has_function_privilege('anon','public.'||signature,'EXECUTE')
      or has_function_privilege('yap_feed_media_worker','public.'||signature,'EXECUTE')then
      raise exception 'Invalid media RPC privileges: %',signature;end if;
    if(select prosecdef from pg_proc where oid=('public.'||signature)::regprocedure)then raise exception 'Exposed definer wrapper';end if;
  end loop;
  for item in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='media'loop
    if has_function_privilege('anon',item.oid,'EXECUTE')or has_function_privilege('authenticated',item.oid,'EXECUTE')
      or has_function_privilege('yap_recommendation_worker',item.oid,'EXECUTE')then raise exception 'Media internals exposed: %',item.proname;end if;
  end loop;
  if exists(select 1 from storage.buckets where id in('feed-uploads','feed-media')and(public or file_size_limit<>5242880))then
    raise exception 'Unsafe feed bucket configuration';end if;
  if(select count(*)from storage.buckets where id in('feed-uploads','feed-media'))<>2 then raise exception 'Buckets missing';end if;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$begin
  begin perform public.reserve_feed_photo(extensions.gen_random_uuid(),extensions.gen_random_uuid(),10,'image/jpeg');
    raise exception 'Missing identity accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
