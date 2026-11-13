begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-0000000000d1', false, false, '{"name":"Profile viewer"}'::jsonb),
  ('10000000-0000-0000-0000-0000000000d2', false, false, '{"name":"Profile target"}'::jsonb);

update public.profiles
set onboarding_completed = true
where id in (
  '10000000-0000-0000-0000-0000000000d1',
  '10000000-0000-0000-0000-0000000000d2'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000d1', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  attempt integer;
begin
  for attempt in 1..20 loop
    perform public.get_viewed_profile(
      '10000000-0000-0000-0000-0000000000d2',
      false
    );
  end loop;

  begin
    perform public.get_viewed_profile(
      '10000000-0000-0000-0000-0000000000d2',
      false
    );
    raise exception 'Profile read quota did not reject request 21';
  exception when sqlstate '42901' then
    if sqlerrm <> 'profile_read_rate_limited' then raise; end if;
  end;
end;
$$;

reset role;

update private.profile_read_limits
set window_started_at = statement_timestamp() - interval '1 minute'
where viewer_user_id = '10000000-0000-0000-0000-0000000000d1'
  and target_user_id = '10000000-0000-0000-0000-0000000000d2';

insert into private.global_account_bans (target_user_id, note)
values ('10000000-0000-0000-0000-0000000000d2', 'profile read quota test');

set local role authenticated;

do $$
begin
  if public.get_profile_view_count(
    '10000000-0000-0000-0000-0000000000d2'
  ) <> 0 then
    raise exception 'Globally banned profile exposed a view count';
  end if;
end;
$$;

reset role;
rollback;
