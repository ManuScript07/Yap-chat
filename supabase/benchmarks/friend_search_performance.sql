\set ON_ERROR_STOP on
\pset pager off
\timing on

begin;

create schema benchmark_friend_search;

create unlogged table benchmark_friend_search.profiles (
  id integer primary key,
  username text not null,
  display_name text not null,
  onboarding_completed boolean not null default true
);

create unique index benchmark_profiles_username_lower_idx
on benchmark_friend_search.profiles (lower(username));

create index benchmark_profiles_display_name_fts_idx
on benchmark_friend_search.profiles using gin (
  to_tsvector('simple'::regconfig, display_name)
)
where onboarding_completed;

\echo ==== STRUCTURAL BENCHMARK: 10k profiles ====
insert into benchmark_friend_search.profiles (id, username, display_name)
select
  value,
  'user_' || lpad(value::text, 7, '0'),
  case
    when value % 100 = 0 then 'Максим Тест ' || value
    when value % 137 = 0 then 'Иван Максимов ' || value
    else 'Пользователь ' || value
  end
from generate_series(1, 10000) value;
analyze benchmark_friend_search.profiles;

\echo -- OLD name substring query (10k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where strpos(lower(display_name), 'макс') > 0
order by lower(display_name), id
limit 10;

\echo -- NEW name word-prefix query (10k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where onboarding_completed
  and to_tsvector('simple'::regconfig, display_name)
    @@ to_tsquery('simple'::regconfig, '''макс'':*')
order by
  (lower(display_name) = 'макс') desc,
  (left(lower(display_name), 4) = 'макс') desc,
  lower(display_name),
  id
limit 10;

\echo ==== STRUCTURAL BENCHMARK: 100k profiles ====
insert into benchmark_friend_search.profiles (id, username, display_name)
select
  value,
  'user_' || lpad(value::text, 7, '0'),
  case
    when value % 100 = 0 then 'Максим Тест ' || value
    when value % 137 = 0 then 'Иван Максимов ' || value
    else 'Пользователь ' || value
  end
from generate_series(10001, 100000) value;
analyze benchmark_friend_search.profiles;

\echo -- OLD name substring query (100k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where strpos(lower(display_name), 'макс') > 0
order by lower(display_name), id
limit 10;

\echo -- NEW name word-prefix query (100k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where onboarding_completed
  and to_tsvector('simple'::regconfig, display_name)
    @@ to_tsquery('simple'::regconfig, '''макс'':*')
order by
  (lower(display_name) = 'макс') desc,
  (left(lower(display_name), 4) = 'макс') desc,
  lower(display_name),
  id
limit 10;

\echo -- NEW exact username query (100k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where lower(username) = 'user_0050000'
limit 1;

\echo ==== STRUCTURAL BENCHMARK: 500k profiles ====
insert into benchmark_friend_search.profiles (id, username, display_name)
select
  value,
  'user_' || lpad(value::text, 7, '0'),
  case
    when value % 100 = 0 then 'Максим Тест ' || value
    when value % 137 = 0 then 'Иван Максимов ' || value
    else 'Пользователь ' || value
  end
from generate_series(100001, 500000) value;
analyze benchmark_friend_search.profiles;

\echo -- OLD name substring query (500k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where strpos(lower(display_name), 'макс') > 0
order by lower(display_name), id
limit 10;

\echo -- NEW name word-prefix query (500k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where onboarding_completed
  and to_tsvector('simple'::regconfig, display_name)
    @@ to_tsquery('simple'::regconfig, '''макс'':*')
order by
  (lower(display_name) = 'макс') desc,
  (left(lower(display_name), 4) = 'макс') desc,
  lower(display_name),
  id
limit 10;

\echo -- NEW exact username query (500k)
explain (analyze, buffers, settings)
select id
from benchmark_friend_search.profiles
where lower(username) = 'user_0250000'
limit 1;

rollback;

\echo ==== ACTUAL RPC BENCHMARK: 100k local auth profiles ====
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

set local session_replication_role = origin;

insert into private.profile_friend_counts (user_id, friends_count)
select md5('friend-search-benchmark-' || value)::uuid, value % 250
from generate_series(0, 99999) value
on conflict (user_id) do update
set friends_count = excluded.friends_count;

analyze public.profiles;
analyze private.profile_friend_counts;

select set_config(
  'request.jwt.claim.sub',
  md5('friend-search-benchmark-0')::uuid::text,
  true
);
set local role authenticated;

\echo -- ACTUAL RPC name prefix, first warm-up
select count(*) from public.search_friend_candidates('макс', 10);

\echo -- ACTUAL RPC name prefix EXPLAIN
explain (analyze, buffers, settings)
select * from public.search_friend_candidates('макс', 10);

\echo -- ACTUAL RPC exact username EXPLAIN
explain (analyze, buffers, settings)
select * from public.search_friend_candidates('@bench_0050000', 10);

reset role;
rollback;

\echo ==== pg_stat_statements entries ====
select
  calls,
  round(mean_exec_time::numeric, 3) as mean_ms,
  rows,
  left(regexp_replace(query, E'\\s+', ' ', 'g'), 120) as query
from pg_stat_statements
where query ilike '%search_friend_candidates%'
order by calls desc, mean_exec_time desc
limit 10;
