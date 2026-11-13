\set ON_ERROR_STOP on
\pset pager off

begin;
set local session_replication_role = replica;

insert into public.profiles (id, username, display_name, onboarding_completed)
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
from generate_series(0, 99999) value;

analyze public.profiles;
analyze private.profile_friend_counts;
select set_config(
  'request.jwt.claim.sub',
  md5('friend-search-benchmark-0')::uuid::text,
  true
);
load 'auto_explain';
set local auto_explain.log_min_duration = 0;
set local auto_explain.log_analyze = on;
set local auto_explain.log_buffers = on;
set local auto_explain.log_nested_statements = on;
set local auto_explain.log_level = notice;
set local role authenticated;

select count(*) from public.search_friend_candidates('макс', 10);
select count(*) from public.search_friend_candidates('@bench_0050000', 10);

reset role;
rollback;
