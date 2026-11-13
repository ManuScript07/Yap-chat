\set ON_ERROR_STOP on
\pset pager off
\timing on

begin;
set local session_replication_role = replica;

insert into public.profiles (
  id,
  username,
  display_name,
  onboarding_completed
)
select
  md5('friend-search-benchmark-' || value)::uuid,
  'bench_' || lpad(value::text, 7, '0'),
  case
    when value % 100 = 0 then 'Максим Тест ' || value
    when value % 137 = 0 then 'Иван Максимов ' || value
    else 'Пользователь ' || value
  end,
  true
from generate_series(0, 99999) value;

insert into public.friendships (user_one_id, user_two_id)
select
  least(
    md5('friend-search-benchmark-' || value)::uuid,
    md5('friend-search-benchmark-' || ((value + 1) % 100000))::uuid
  ),
  greatest(
    md5('friend-search-benchmark-' || value)::uuid,
    md5('friend-search-benchmark-' || ((value + 1) % 100000))::uuid
  )
from generate_series(0, 99999) value;

insert into public.friend_requests (sender_id, recipient_id)
select
  md5('friend-search-benchmark-' || value)::uuid,
  md5('friend-search-benchmark-' || (value + 50000))::uuid
from generate_series(0, 19999) value;

set local session_replication_role = origin;

insert into private.profile_friend_counts (user_id, friends_count)
select md5('friend-search-benchmark-' || value)::uuid, value % 250
from generate_series(0, 99999) value
on conflict (user_id) do update
set friends_count = excluded.friends_count;

analyze public.profiles;
analyze private.profile_friend_counts;
analyze public.friendships;
analyze public.friend_requests;

create function pg_temp.measure_friend_search(search_text text, run_count integer)
returns table (p50_ms numeric, p95_ms numeric)
language plpgsql
security definer
set search_path = ''
as $$
declare
  durations double precision[] := '{}';
  started_at timestamptz;
  run integer;
begin
  for run in 1..run_count loop
    started_at := clock_timestamp();
    perform *
    from public.search_friend_candidates(search_text, 10);
    durations := array_append(
      durations,
      extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;

  return query
  select
    percentile_cont(0.5) within group (order by duration)::numeric,
    percentile_cont(0.95) within group (order by duration)::numeric
  from unnest(durations) duration;
end;
$$;

create function pg_temp.assert_friend_search_behavior()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate_count integer;
  exact_relationship text;
  exact_request_id uuid;
begin
  select count(*)
  into candidate_count
  from public.search_friend_candidates('макс', 10);
  if candidate_count <> 10 then
    raise exception 'expected 10 name candidates, got %', candidate_count;
  end if;

  select count(*)
  into candidate_count
  from public.search_friend_candidates('ма', 10);
  if candidate_count <> 0 then
    raise exception 'short name search returned % candidates', candidate_count;
  end if;

  select count(*)
  into candidate_count
  from public.search_friend_candidates('@bench_0000001', 10);
  if candidate_count <> 0 then
    raise exception 'existing friend was returned by exact username search';
  end if;

  select candidate.relationship, candidate.request_id
  into exact_relationship, exact_request_id
  from public.search_friend_candidates('@bench_0050000', 10) candidate;
  if exact_relationship <> 'outgoing' or exact_request_id is null then
    raise exception 'pending request metadata was not returned correctly';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  md5('friend-search-benchmark-0')::uuid::text,
  true
);

\echo -- OLD RPC-equivalent name substring EXPLAIN
explain (analyze, buffers, settings)
with normalized as (
  select 'макс'::text as query
)
select
  profile.id,
  case
    when private.friend_count_visible_to(profile.id, auth.uid())
      then private.friend_count_for(profile.id)
    else null
  end as friend_count
from public.profiles profile
cross join normalized
left join public.friendships friendship
  on friendship.user_one_id = least(profile.id, auth.uid())
 and friendship.user_two_id = greatest(profile.id, auth.uid())
left join public.friend_requests request
  on request.pair_user_one_id = least(profile.id, auth.uid())
 and request.pair_user_two_id = greatest(profile.id, auth.uid())
where profile.id <> auth.uid()
  and (
    strpos(lower(profile.username), normalized.query) > 0
    or strpos(lower(profile.display_name), normalized.query) > 0
  )
order by
  (lower(profile.username) = normalized.query) desc,
  (left(lower(profile.username), length(normalized.query)) = normalized.query) desc,
  lower(profile.display_name),
  profile.id
limit 10;

set local role authenticated;

\echo -- FUNCTIONAL ASSERTIONS
select pg_temp.assert_friend_search_behavior();

\echo -- ACTUAL RPC latency percentiles, 20 warm-cache calls
select 'name_prefix' as search_type, *
from pg_temp.measure_friend_search('макс', 20)
union all
select 'exact_username', *
from pg_temp.measure_friend_search('@bench_0050000', 20);

\echo -- ACTUAL RPC name prefix warm-up
select count(*) from public.search_friend_candidates('макс', 10);

\echo -- ACTUAL RPC name prefix EXPLAIN
explain (analyze, buffers, settings)
select * from public.search_friend_candidates('макс', 10);

\echo -- ACTUAL RPC exact username EXPLAIN
explain (analyze, buffers, settings)
select * from public.search_friend_candidates('@bench_0050000', 10);

reset role;
rollback;

select
  calls,
  round(mean_exec_time::numeric, 3) as mean_ms,
  rows,
  left(regexp_replace(query, E'\\s+', ' ', 'g'), 120) as query
from pg_stat_statements
where query ilike '%search_friend_candidates%'
order by calls desc, mean_exec_time desc
limit 10;
