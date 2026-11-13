begin;

insert into auth.users(id, is_sso_user, is_anonymous, raw_user_meta_data)
values ('75000000-0000-4000-8000-000000000001', false, false, '{"name":"Formatting author"}'),
       ('75000000-0000-4000-8000-000000000002', false, false, '{"name":"Formatting viewer"}');

do $$
declare
  author constant uuid := '75000000-0000-4000-8000-000000000001';
  viewer constant uuid := '75000000-0000-4000-8000-000000000002';
  post constant uuid := '75000000-0000-4000-8000-000000000003';
  quote_post constant uuid := '75000000-0000-4000-8000-000000000004';
  body constant text := U&'a\+01F680e\0301z';
  formatted constant jsonb := '{"version":1,"spans":[{"start":1,"end":4,"style":"italic"},{"start":0,"end":2,"style":"bold"}]}';
  canonical constant jsonb := '{"version":1,"spans":[{"start":0,"end":2,"style":"bold"},{"start":1,"end":4,"style":"italic"}]}';
  updated constant jsonb := '{"version":1,"spans":[{"start":1,"end":2,"style":"underline"},{"start":1,"end":2,"style":"strikethrough"}]}';
  empty_format constant jsonb := '{"version":1,"spans":[]}';
  response jsonb;
  bad jsonb;
begin
  if has_function_privilege('anon', 'public.publish_feed_post(uuid,text,text,text,uuid[],jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.edit_feed_post(uuid,integer,text,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.create_feed_repost(uuid,uuid,text,text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'private.normalize_feed_formatting(text,jsonb)', 'execute') then
    raise exception 'Unexpected formatting function grant';
  end if;

  perform set_config('request.jwt.claim.sub', author::text, true);
  set local role authenticated;
  for bad in select value from jsonb_array_elements('[
    null, 42, {"version":2,"spans":[]}, {"version":1,"spans":{}},
    {"version":1,"spans":[null]}, {"version":1,"spans":[{"start":0,"end":6,"style":"bold"}]},
    {"version":1,"spans":[{"start":2,"end":2,"style":"bold"}]},
    {"version":1,"spans":[{"start":0,"end":2,"style":"html"}]},
    {"version":1,"spans":[{"start":0,"end":2,"style":"bold","html":"x"}]},
    {"version":1,"spans":[{"start":0,"end":3,"style":"bold"},{"start":2,"end":4,"style":"bold"}]},
    {"version":1,"spans":[{"start":0,"end":1.5,"style":"bold"}]}
  ]') loop
    begin
      perform public.publish_feed_post(post, body, 'public', 'en', '{}', null, bad);
      raise exception 'Invalid formatting accepted: %', bad;
    exception when invalid_parameter_value then
      if sqlerrm <> 'invalid_post_formatting' then raise; end if;
    end;
  end loop;

  response := public.publish_feed_post(post, body, 'public', 'en', '{}', null, formatted);
  if response->'formatting' is distinct from canonical or response->>'text' is distinct from body then
    raise exception 'Formatting did not round-trip in code-point order';
  end if;
  if public.publish_feed_post(post, body, 'public', 'en', '{}', null, canonical)->'formatting' is distinct from canonical then
    raise exception 'Equivalent span order did not replay';
  end if;
  begin
    perform public.publish_feed_post(post, body, 'public', 'en', '{}', null, updated);
    raise exception 'Conflicting formatting reused publication id';
  exception when unique_violation then null;
  end;

  response := public.edit_feed_post(post, 1, body);
  if response->'formatting' is distinct from canonical or response->>'version' <> '1' then
    raise exception 'A legacy no-op erased formatting';
  end if;
  response := public.edit_feed_post(post, 1, body, updated);
  if response->>'version' is distinct from '2' or response->'edited' is distinct from 'true'::jsonb then
    raise exception 'A format-only edit did not version the post';
  end if;
  begin
    perform public.edit_feed_post(post, 1, body, empty_format);
    raise exception 'A stale edit succeeded';
  exception when serialization_failure then null;
  end;
  reset role;
  if not exists (select from recsys.index_jobs where post_id = post and post_version = 2) then
    raise exception 'The worker cannot index the new content version';
  end if;

  perform set_config('request.jwt.claim.sub', viewer::text, true);
  set local role authenticated;
  response := public.get_feed_post(post);
  if jsonb_array_length(response#>'{formatting,spans}') is distinct from 2 then
    raise exception 'The viewer did not receive formatting';
  end if;
  begin
    perform public.edit_feed_post(post, 2, body, empty_format);
    raise exception 'A viewer edited somebody else''s formatting';
  exception when no_data_found then null;
  end;
  perform public.create_feed_repost(quote_post, post, body, 'public', 'en', canonical);
  if public.get_feed_post(quote_post)->'formatting' is distinct from canonical then
    raise exception 'Quote formatting did not round-trip';
  end if;
  reset role;

  perform set_config('request.jwt.claim.sub', author::text, true);
  set local role authenticated;
  if public.edit_feed_post(post, 2, 'new plain text')->'formatting' is distinct from empty_format then
    raise exception 'A legacy text change retained stale ranges';
  end if;
  reset role;
end $$;

rollback;
