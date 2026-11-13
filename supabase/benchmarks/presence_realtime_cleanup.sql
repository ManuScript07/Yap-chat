\set ON_ERROR_STOP on

begin;

drop policy if exists "Benchmark global presence receive" on realtime.messages;
drop policy if exists "Benchmark global presence track" on realtime.messages;

delete from auth.users
where raw_user_meta_data ->> 'benchmark_fixture' = 'presence-realtime';

commit;
