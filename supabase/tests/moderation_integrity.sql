begin;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'public.is_push_message_deliverable(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated users can call push delivery check';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.is_push_message_deliverable(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Push worker lost delivery-check access';
  end if;
end;
$$;

insert into private.app_public_content (singleton, support_email)
values (true, 'support@example.com')
on conflict (singleton) do update
set support_email = excluded.support_email,
    updated_at = now();

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000071', false, false, '{"name":"Reporter"}'::jsonb),
  ('10000000-0000-0000-0000-000000000072', false, false, '{"name":"Target one"}'::jsonb),
  ('10000000-0000-0000-0000-000000000073', false, false, '{"name":"Target two"}'::jsonb),
  ('10000000-0000-0000-0000-000000000074', false, false, '{"name":"Target three"}'::jsonb),
  ('10000000-0000-0000-0000-000000000075', false, false, '{"name":"Target four"}'::jsonb),
  ('10000000-0000-0000-0000-000000000076', false, false, '{"name":"Target five"}'::jsonb),
  ('10000000-0000-0000-0000-000000000077', false, false, '{"name":"Target six"}'::jsonb);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000071',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000071","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.submit_user_report(
    '10000000-0000-0000-0000-000000000072', 'spam'
  );
  begin
    perform public.submit_user_report(
      '10000000-0000-0000-0000-000000000072', 'scam'
    );
    raise exception 'The per-target seven-day report limit was bypassed';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'user_report_target_rate_limited' then raise; end if;
  end;

  perform public.submit_user_report('10000000-0000-0000-0000-000000000073', 'scam');
  perform public.submit_user_report('10000000-0000-0000-0000-000000000074', 'pornography');
  perform public.submit_user_report('10000000-0000-0000-0000-000000000075', 'other');
  perform public.submit_user_report('10000000-0000-0000-0000-000000000076', 'spam');
  begin
    perform public.submit_user_report('10000000-0000-0000-0000-000000000077', 'spam');
    raise exception 'The five-target daily report limit was bypassed';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'user_report_daily_rate_limited' then raise; end if;
  end;
end;
$$;

reset role;

insert into private.global_account_bans (target_user_id, note)
values ('10000000-0000-0000-0000-000000000072', 'moderation test');

do $$
begin
  if not private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000072'
  ) then
    raise exception 'Global ban link was not created';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000072',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000072","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  access_banned boolean;
  access_support_email text;
  visible_profiles integer;
begin
  select is_banned, support_email
  into access_banned, access_support_email
  from public.get_my_account_access();
  if access_banned is not true then
    raise exception 'Banned user did not receive the narrow access status';
  end if;
  if access_support_email <> 'support@example.com' then
    raise exception 'Account access response did not include support email';
  end if;
  select count(*) into visible_profiles
  from public.profiles
  where id = '10000000-0000-0000-0000-000000000072';
  if visible_profiles <> 0 then
    raise exception 'Restrictive RLS did not hide profile rows for banned user';
  end if;
end;
$$;

reset role;
set local role authenticator;
select set_config('request.path', 'rpc/get_my_account_access', true);
select private.enforce_data_api_account_access();
select set_config('request.path', 'rpc/get_friends', true);
do $$
begin
  begin
    perform private.enforce_data_api_account_access();
    raise exception 'Data API pre-request guard allowed banned account';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'account_globally_banned' then raise; end if;
  end;
end;
$$;

reset role;
update private.global_account_bans
set revoked_at = now()
where target_user_id = '10000000-0000-0000-0000-000000000072';

do $$
declare
  historical_ban_count integer;
begin
  if private.is_account_globally_banned(
    '10000000-0000-0000-0000-000000000072'
  ) then
    raise exception 'Revoked global ban still restricted the account';
  end if;
  select target_global_ban_count
  into historical_ban_count
  from private.moderation_user_reports
  where target_user_id = '10000000-0000-0000-0000-000000000072'
  limit 1;
  if historical_ban_count <> 1 then
    raise exception 'Historical global ban count was not retained';
  end if;
end;
$$;

rollback;
