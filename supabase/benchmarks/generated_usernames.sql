-- Local, isolated benchmark: no application rows or sequence are modified.
-- Run with psql after applying the generated-usernames migration. Timing is
-- database-side, excludes Docker/network latency, and reports medians.
begin;
set local statement_timeout = '60s';
create temporary table username_benchmark_profiles (username text not null);
create unique index username_benchmark_lower_unique
  on username_benchmark_profiles (lower(username));
create temporary sequence username_benchmark_sequence;
create temporary table username_benchmark_samples (
  occupied integer, implementation text, milliseconds double precision
);

create function pg_temp.old_username_generator()
returns text language plpgsql set search_path = '' as $$
declare
  alphabet constant text := '0123456789abcdefghijklmnopqrstuvwxyz';
  candidate text;
  encoded text;
  sequence_value bigint;
begin
  loop
    sequence_value := nextval('pg_temp.username_benchmark_sequence'::regclass);
    encoded := '';
    while sequence_value > 0 loop
      encoded := substr(alphabet, (sequence_value % length(alphabet))::integer + 1, 1) || encoded;
      sequence_value := sequence_value / length(alphabet);
    end loop;
    if length(encoded) > 7 then raise exception 'Generated username sequence is exhausted'; end if;
    candidate := 'u' || lpad(encoded, 7, '0');
    exit when not exists (
      select 1 from pg_temp.username_benchmark_profiles where lower(username) = candidate
    );
  end loop;
  return candidate;
end;
$$;

do $$
declare definition text;
begin
  definition := pg_get_functiondef('private.generate_unique_username_impl()'::regprocedure);
  definition := replace(definition, 'private.generate_unique_username_impl()', 'pg_temp.new_username_generator()');
  definition := replace(definition, 'public.username_sequence', 'pg_temp.username_benchmark_sequence');
  definition := replace(definition, 'public.profiles', 'pg_temp.username_benchmark_profiles');
  execute definition;
end;
$$;

insert into username_benchmark_profiles
select 'manual_' || to_hex(number) from generate_series(1, 100000) number;
analyze username_benchmark_profiles;

do $$
declare occupied_count integer; started_at timestamptz; elapsed_ms double precision; candidate text;
begin
  foreach occupied_count in array array[0, 100, 1000, 10000] loop
    delete from pg_temp.username_benchmark_profiles where username like 'u%';
    insert into pg_temp.username_benchmark_profiles
    select private.generated_username_for_number(number)
    from generate_series(1, occupied_count) number;
    analyze pg_temp.username_benchmark_profiles;

    for repetition in 1..21 loop
      perform setval('pg_temp.username_benchmark_sequence', 1, false);
      started_at := clock_timestamp();
      candidate := pg_temp.old_username_generator();
      elapsed_ms := extract(epoch from clock_timestamp() - started_at) * 1000;
      if candidate <> private.generated_username_for_number(occupied_count + 1) then
        raise exception 'Old allocator returned unexpected candidate';
      end if;
      if repetition > 1 then
        insert into pg_temp.username_benchmark_samples values
          (occupied_count, 'old', elapsed_ms);
      end if;

      perform setval('pg_temp.username_benchmark_sequence', 1, false);
      started_at := clock_timestamp();
      candidate := pg_temp.new_username_generator();
      elapsed_ms := extract(epoch from clock_timestamp() - started_at) * 1000;
      if candidate <> private.generated_username_for_number(occupied_count + 1) then
        raise exception 'New allocator returned unexpected candidate';
      end if;
      if repetition > 1 then
        insert into pg_temp.username_benchmark_samples values
          (occupied_count, 'new', elapsed_ms);
      end if;
    end loop;
  end loop;
end;
$$;

select occupied, implementation,
  round(percentile_cont(0.5) within group (order by milliseconds)::numeric, 3) as median_ms,
  round(avg(milliseconds)::numeric, 3) as average_ms
from username_benchmark_samples group by occupied, implementation order by occupied, implementation;

-- Explain the actual allocator statement, not a separately copied query that
-- could drift from production or accidentally reintroduce formatter calls.
do $$
declare definition text; batch_query text; plan_line record;
begin
  definition := pg_get_functiondef('pg_temp.new_username_generator()'::regprocedure);
  batch_query := 'with tickets as materialized (' || split_part(
    split_part(definition, 'with tickets as materialized (', 2),
    'if candidate is not null then', 1
  );
  batch_query := replace(batch_query,
    'select available.username into candidate', 'select available.username');
  perform setval('pg_temp.username_benchmark_sequence', 1, false);
  for plan_line in execute 'explain (analyze, buffers, costs off) ' || batch_query loop
    raise notice '%', plan_line."QUERY PLAN";
  end loop;
end;
$$;
rollback;
