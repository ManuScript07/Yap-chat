begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  (
    '10000000-0000-0000-0000-000000000011',
    false,
    false,
    '{"name": "Viewer"}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000012',
    false,
    false,
    '{"name": "Target"}'::jsonb
  );

update public.profiles
set onboarding_completed = true
where id in (
  '10000000-0000-0000-0000-000000000011',
  '10000000-0000-0000-0000-000000000012'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000011',
  true
);
set local role authenticated;

do $$
declare
  viewer_id constant uuid := '10000000-0000-0000-0000-000000000011';
  profile_id constant uuid := '10000000-0000-0000-0000-000000000012';
begin
  if public.record_profile_view(profile_id) <> 1 then
    raise exception 'First profile view was not counted';
  end if;
  if public.record_profile_view(profile_id) <> 1 then
    raise exception 'View rate limit did not suppress a duplicate';
  end if;
end;
$$;

reset role;

update private.profile_view_counters
set last_viewed_at = now() - interval '21 minutes'
where profile_id = '10000000-0000-0000-0000-000000000012'
  and viewer_id = '10000000-0000-0000-0000-000000000011';

insert into private.profile_view_daily_counters (
  profile_id, viewer_id, viewed_on, view_count, last_viewed_at
) values (
  '10000000-0000-0000-0000-000000000012',
  '10000000-0000-0000-0000-000000000011',
  ((now() at time zone 'utc')::date - 7),
  99,
  now() - interval '7 days'
);

set local role authenticated;

do $$
declare
  profile_id constant uuid := '10000000-0000-0000-0000-000000000012';
begin
  if public.record_profile_view(profile_id) <> 2 then
    raise exception 'A view after the rate-limit window was not counted';
  end if;
  if public.get_profile_view_count(profile_id) <> 2 then
    raise exception 'Views older than seven calendar days were included';
  end if;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1
    from private.profile_view_daily_counters
    where viewed_on < ((now() at time zone 'utc')::date - 6)
  ) then
    raise exception 'Expired profile-view aggregates were not pruned';
  end if;
end;
$$;

rollback;
