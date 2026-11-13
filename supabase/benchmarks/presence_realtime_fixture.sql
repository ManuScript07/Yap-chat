\set ON_ERROR_STOP on

-- Local-only fixture for presence_realtime_benchmark.mjs. It is deliberately
-- isolated by metadata so cleanup cannot affect normal local accounts.
begin;

delete from auth.users
where raw_user_meta_data ->> 'benchmark_fixture' = 'presence-realtime';

with fixture_users as (
  select '00000000-0000-0000-0000-00000000b000'::uuid as id
  union all
  select (
    '00000000-0000-0000-0000-00000000c' || lpad(value::text, 3, '0')
  )::uuid
  from generate_series(1, 100) value
)
insert into auth.users (
  id,
  is_sso_user,
  is_anonymous,
  raw_user_meta_data
)
select
  id,
  false,
  false,
  jsonb_build_object('benchmark_fixture', 'presence-realtime')
from fixture_users;

update public.profiles
set
  onboarding_completed = true,
  birth_date = date '1990-01-01',
  display_name = 'Presence benchmark',
  last_seen_at = statement_timestamp()
where id in (
    select id
    from auth.users
    where raw_user_meta_data ->> 'benchmark_fixture' = 'presence-realtime'
  );

insert into public.friendships (user_one_id, user_two_id)
select
  least('00000000-0000-0000-0000-00000000b000'::uuid, recipient.id),
  greatest('00000000-0000-0000-0000-00000000b000'::uuid, recipient.id)
from (
  select (
    '00000000-0000-0000-0000-00000000c' || lpad(value::text, 3, '0')
  )::uuid as id
  from generate_series(1, 20) value
) recipient;

-- These two policies reproduce only the former global Presence room. They
-- exist solely while the benchmark runs and are removed by the cleanup file.
drop policy if exists "Benchmark global presence receive" on realtime.messages;
drop policy if exists "Benchmark global presence track" on realtime.messages;
create policy "Benchmark global presence receive"
on realtime.messages
for select to authenticated
using (
  realtime.messages.extension = 'presence'
  and (select realtime.topic()) = 'online'
);
create policy "Benchmark global presence track"
on realtime.messages
for insert to authenticated
with check (
  realtime.messages.extension = 'presence'
  and (select realtime.topic()) = 'online'
);

commit;
