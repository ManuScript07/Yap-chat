begin;
do $$declare r record; role_name text;begin
 for r in select c.oid,c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='media'and c.relkind='r'loop
  if not r.relrowsecurity then raise exception 'Media RLS missing: %',r.relname;end if;
  foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
   if has_table_privilege(role_name,r.oid,'SELECT,INSERT,UPDATE,DELETE')then raise exception 'Raw media grant: % %',role_name,r.relname;end if;
  end loop;
 end loop;
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private'and p.proname in('media_busy','release_media_reservation','adjust_media_reservation','account_media_cleanup','charge_media_cleanup',
 'observe_cleanup_attempt','account_media_photo','release_media_draft','time_media_photo','observe_media_photo','release_media_processing_slot','validate_feed_upload_metadata')loop
  foreach role_name in array array['anon','authenticated','yap_recommendation_worker','yap_feed_media_worker']loop
   if has_function_privilege(role_name,r.oid,'EXECUTE')then raise exception 'Private accounting exposed: % %',role_name,r.proname;end if;
  end loop;
 end loop;
 if not has_function_privilege('authenticated','private.feed_upload_metadata_matches(text,jsonb)','EXECUTE')
 or has_function_privilege('anon','private.feed_upload_metadata_matches(text,jsonb)','EXECUTE')
 or has_function_privilege('yap_feed_media_worker','private.feed_upload_metadata_matches(text,jsonb)','EXECUTE')then
 raise exception 'Invalid upload preflight capability';end if;
 if not exists(select 1 from pg_trigger where tgrelid='storage.objects'::regclass and tgname='feed_upload_metadata_guard'and not tgisinternal)then
 raise exception 'Actual upload byte guard missing';end if;
 if exists(select 1 from media.capacity c where c.active<>(select count(*)from media.reservations)
 or c.unfinished<>(select count(*)from media.reservations where unfinished)
 or c.reserved_bytes<>coalesce((select sum(bytes)from media.reservations),0)
 or c.temporary_bytes<>coalesce((select sum(estimated_bytes)from media.cleanup_jobs),0))then
 raise exception 'Media accounting drift';end if;
 if(select count(*)from media.processing_slots)<>8 then raise exception 'Global processing slots missing';end if;
 if(select count(*)from pg_trigger where tgname in('media_reservation_release','media_reservation_adjust','media_cleanup_release','media_cleanup_charge','media_cleanup_failure','feed_photo_observability')and tgdeferrable and tginitdeferred)<>6 then
 raise exception 'Accounting must be deferred until source changes finish';end if;
end $$;
rollback;
