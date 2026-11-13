-- Executed inside a rollback transaction by conversation_window_seek_local.mjs.
-- The runner creates pg_temp.legacy_conversation_window from the ORIGINAL
-- migration, so equivalence does not share the optimized implementation.
create temp table window_seek_checks (
  checks integer not null,
  legacy_base_ms double precision not null default 0,
  current_base_ms double precision not null default 0,
  legacy_reactions_ms double precision not null default 0,
  current_reactions_ms double precision not null default 0
);
insert into window_seek_checks values (0);
create temp table window_seek_slow_cases (
  case_number integer, actor uuid, target uuid, after_id uuid, page_size integer,
  legacy_base_ms double precision, current_base_ms double precision,
  legacy_reactions_ms double precision, current_reactions_ms double precision
);

create function pg_temp.assert_same_window(
  conversation uuid, target uuid, after_at timestamptz, after_id uuid, size integer
) returns void language plpgsql as $$
declare
  expected jsonb; actual jsonb; expected_reactions jsonb; actual_reactions jsonb;
  t0 timestamptz; t1 timestamptz; t2 timestamptz; t3 timestamptz; t4 timestamptz;
  elapsed double precision[]; case_number integer;
begin
  t0 := clock_timestamp();
  select coalesce(jsonb_agg(to_jsonb(m)), '[]')
  into expected from pg_temp.legacy_conversation_window(conversation, target, after_at, after_id, size) m;
  t1 := clock_timestamp();
  select coalesce(jsonb_agg(to_jsonb(m)), '[]')
  into actual from private.get_conversation_message_window_impl(conversation, target, after_at, after_id, size) m;
  t2 := clock_timestamp();
  if actual is distinct from expected then
    raise exception 'Window projection changed: actor %, target %, after %, size %', auth.uid(), target, after_id, size;
  end if;
  select coalesce(jsonb_agg(to_jsonb(m)), '[]')
  into expected_reactions from (
    select r.*, private.message_reaction_state(r.id) as reaction_state
    from pg_temp.legacy_conversation_window(conversation, target, after_at, after_id, size) r
  ) m;
  t3 := clock_timestamp();
  select coalesce(jsonb_agg(to_jsonb(m)), '[]')
  into actual_reactions from private.get_conversation_window_with_reactions_impl(conversation, target, after_at, after_id, size) m;
  t4 := clock_timestamp();
  if actual_reactions is distinct from expected_reactions then
    raise exception 'Window reactions changed: target %, after %, size %', target, after_id, size;
  end if;
  elapsed := array[
    extract(epoch from t1-t0)*1000, extract(epoch from t2-t1)*1000,
    extract(epoch from t3-t2)*1000, extract(epoch from t4-t3)*1000
  ];
  update window_seek_checks set checks = checks + 1,
    legacy_base_ms = legacy_base_ms + elapsed[1],
    current_base_ms = current_base_ms + elapsed[2],
    legacy_reactions_ms = legacy_reactions_ms + elapsed[3],
    current_reactions_ms = current_reactions_ms + elapsed[4]
  returning checks into case_number;
  if greatest(elapsed[1], elapsed[2], elapsed[3], elapsed[4]) >= 50 then
    insert into window_seek_slow_cases values (
      case_number, auth.uid(), target, after_id, size,
      elapsed[1], elapsed[2], elapsed[3], elapsed[4]
    );
  end if;
  if case_number = 1 or case_number % 50 = 0 then
    raise notice 'Window matrix: case %, last query times old/new/old+reactions/new+reactions ms: %',
      case_number, elapsed;
  end if;
end; $$;

insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('e7100000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid, false, false, '{}'
from generate_series(1,4) i;
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
('e7200000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000002','e7100000-0000-0000-0000-000000000001'),
('e7200000-0000-0000-0000-000000000002','e7100000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000003','e7100000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values
('e7200000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000001'),
('e7200000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000002'),
('e7200000-0000-0000-0000-000000000002','e7100000-0000-0000-0000-000000000001'),
('e7200000-0000-0000-0000-000000000002','e7100000-0000-0000-0000-000000000003');

-- Suppress synthetic fixture broadcasts only, never on the real RPC calls.
set local session_replication_role=replica;
insert into public.messages(id,conversation_id,sender_id,type,text,latitude,longitude,created_at,deleted_for_everyone_at)
select md5('window-seek:'||i)::uuid, 'e7200000-0000-0000-0000-000000000001',
  case when i%2=0 then 'e7100000-0000-0000-0000-000000000001'::uuid else 'e7100000-0000-0000-0000-000000000002'::uuid end,
  case i%4 when 0 then 'image' when 1 then 'audio' when 2 then 'location' else 'text' end,
  'message '||i, case when i%4=2 then 55.75 end, case when i%4=2 then 37.61 end,
  '2026-01-01'::timestamptz + (i/10)*interval '1 second' + (i%3)*interval '1 microsecond',
  case when i%23=0 then '2026-01-02'::timestamptz end
from generate_series(1,600) i;
update public.messages m set reply_to_message_id=md5('window-seek:'||(i-20))::uuid
from generate_series(21,600) i where m.id=md5('window-seek:'||i)::uuid;
insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
values ('e7300000-0000-0000-0000-000000000001','e7200000-0000-0000-0000-000000000002',
  'e7100000-0000-0000-0000-000000000003','text','foreign anchor','2026-01-01');
insert into public.message_hidden_for_users(message_id,user_id)
select md5('window-seek:'||i)::uuid,
  case when i%17=0 then 'e7100000-0000-0000-0000-000000000001'::uuid else 'e7100000-0000-0000-0000-000000000002'::uuid end
from generate_series(1,600) i where i%17=0 or i%19=0;
insert into public.message_receipts(message_id,user_id,read_at)
select md5('window-seek:'||i)::uuid, 'e7100000-0000-0000-0000-000000000002', '2026-01-03'::timestamptz
from generate_series(1,600) i where i%7=0;
insert into public.message_attachments(id,message_id,position,kind,storage_path,mime_type,size_bytes,width,height,duration_ms,waveform,deleted_at)
select md5('window-seek-attachment:'||i||':'||p)::uuid, md5('window-seek:'||i)::uuid, p,
  case when i%4=0 then 'image' else 'audio' end,
  'fixture/'||i||'/'||p, case when i%4=0 then 'image/jpeg' else 'audio/aac' end, 1024,
  case when i%4=0 then 640 end, case when i%4=0 then 480 end,
  case when i%4=1 then 1200 end, '[0.1,0.5,0.2]'::jsonb,
  case when p=1 then '2026-01-02'::timestamptz end
from generate_series(1,600) i cross join generate_series(0,2) p
where i%4=0 or (i%4=1 and p=0);
insert into private.message_reaction_versions(message_id,revision)
select md5('window-seek:'||i)::uuid, 9 from generate_series(1,600) i where i%11=0;
insert into private.message_reactions(message_id,user_id,code,revision,operation_id,has_reacted)
select md5('window-seek:'||i)::uuid,
  ('e7100000-0000-0000-0000-'||lpad(u::text,12,'0'))::uuid,
  case when u=1 then 'heart' else 'fire' end, 3,
  md5('window-seek-reaction:'||i||':'||u)::uuid, true
from generate_series(1,600) i cross join generate_series(1,2) u where i%11=0;
set local session_replication_role=origin;

-- Bulk fixture loading bypasses derived state; restore it before exercising
-- real read/delete operations. Older baseline schemas have no projection.
do $f$begin
  if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
    perform private.rebuild_chat_unread_projection(array[
      'e7200000-0000-0000-0000-000000000001',
      'e7200000-0000-0000-0000-000000000002']::uuid[]);
  end if;
end $f$;

do $$
declare actor uuid; target uuid; at_time timestamptz; size integer; i integer; cleared boolean;
begin
  foreach cleared in array array[false,true] loop
    if cleared then
      update public.conversation_members set cleared_at='2026-01-01 00:00:30+00'
      where conversation_id='e7200000-0000-0000-0000-000000000001';
    end if;
    foreach actor in array array['e7100000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000002']::uuid[] loop
      perform set_config('request.jwt.claim.sub',actor::text,true);
      foreach i in array array[1,2,17,23,69,70,289,299,300,301,330,500,550,599,600] loop
        target:=md5('window-seek:'||i)::uuid;
        select created_at into at_time from public.messages where id=target;
        foreach size in array array[null,-10,0,1,2,3,7,59,60,61,2147483647]::integer[] loop
          perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001',target,null,null,size);
          perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001',null,at_time,target,size);
        end loop;
      end loop;
      -- Missing/deleted/foreign anchors, a cursor with no corresponding row,
      -- and empty/nonexistent conversations retain their old behavior.
      perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001','e7300000-0000-0000-0000-000000000001',null,null,60);
      perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001','ffffffff-ffff-ffff-ffff-ffffffffffff',null,null,60);
      perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001',null,'2026-01-01 00:00:35.000001+00','ffffffff-ffff-ffff-ffff-ffffffffffff',60);
      perform pg_temp.assert_same_window('ffffffff-ffff-ffff-ffff-ffffffffffff',null,'2026-01-01','ffffffff-ffff-ffff-ffff-ffffffffffff',60);
    end loop;
  end loop;
  -- Non-member and absent authentication must never expose either mode.
  foreach actor in array array['e7100000-0000-0000-0000-000000000004',null]::uuid[] loop
    perform set_config('request.jwt.claim.sub',coalesce(actor::text,''),true);
    perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001',md5('window-seek:550')::uuid,null,null,60);
    perform pg_temp.assert_same_window('e7200000-0000-0000-0000-000000000001',null,'2026-01-01','ffffffff-ffff-ffff-ffff-ffffffffffff',60);
    if exists(select 1 from private.get_conversation_message_window_impl(
        'e7200000-0000-0000-0000-000000000001',md5('window-seek:550')::uuid)) then
      raise exception 'Non-member saw window content';
    end if;
  end loop;
end; $$;

-- Validate errors independently of membership, as in the old implementation.
do $$
declare args record;
begin
  for args in select * from (values
    (null::uuid,null::uuid,null::timestamptz,null::uuid),
    ('e7200000-0000-0000-0000-000000000001'::uuid,null::uuid,null::timestamptz,null::uuid),
    ('e7200000-0000-0000-0000-000000000001'::uuid,md5('window-seek:550')::uuid,'2026-01-01'::timestamptz,null::uuid),
    ('e7200000-0000-0000-0000-000000000001'::uuid,md5('window-seek:550')::uuid,null::timestamptz,md5('window-seek:550')::uuid),
    ('e7200000-0000-0000-0000-000000000001'::uuid,null::uuid,'2026-01-01'::timestamptz,null::uuid),
    ('e7200000-0000-0000-0000-000000000001'::uuid,null::uuid,null::timestamptz,md5('window-seek:550')::uuid)
  ) v(chat,target,at_time,after_id) loop
    begin
      perform * from private.get_conversation_message_window_impl(args.chat,args.target,args.at_time,args.after_id,60);
      raise exception 'Invalid cursor accepted';
    exception when invalid_parameter_value then null; end;
  end loop;
  if has_function_privilege('anon','private.get_conversation_message_window_impl(uuid,uuid,timestamptz,uuid,integer)','EXECUTE')
    or has_function_privilege('anon','public.get_conversation_message_window(uuid,uuid,timestamptz,uuid,integer)','EXECUTE') then
    raise exception 'Window permissions expanded to anon';
  end if;
  if not (select prosecdef and provolatile='s' and proconfig @> array['search_path=""']
      from pg_proc where oid='private.get_conversation_message_window_impl(uuid,uuid,timestamptz,uuid,integer)'::regprocedure)
    or (select prosecdef from pg_proc where oid='public.get_conversation_message_window(uuid,uuid,timestamptz,uuid,integer)'::regprocedure) then
    raise exception 'Window security/snapshot contract changed';
  end if;
end; $$;

select json_build_object(
  'equivalent_window_cases', checks,
  'query_totals_ms', json_build_object(
    'legacy_base', legacy_base_ms, 'current_base', current_base_ms,
    'legacy_reactions', legacy_reactions_ms, 'current_reactions', current_reactions_ms
  ),
  'slow_cases', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from window_seek_slow_cases s)
) from window_seek_checks;
