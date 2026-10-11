-- Pin the private formatter for the database advisor as well as callers.
-- Keep the allocation query self-contained: a function-level SET prevents
-- SQL-function inlining and would otherwise add a call for every batch ticket.
alter function private.generated_username_for_number(bigint)
  set search_path = '';

create or replace function private.generate_unique_username_impl()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := '0123456789abcdefghijklmnopqrstuvwxyz';
  candidate text;
  encoded text := '';
  sequence_value bigint;
begin
  -- Preserve the one-ticket, one-index-lookup collision-free path.
  sequence_value := nextval('public.username_sequence'::regclass);
  if sequence_value > 78364164095 then
    raise exception 'Generated username sequence is exhausted';
  end if;
  while sequence_value > 0 loop
    encoded := substr(alphabet, (sequence_value % 36)::integer + 1, 1) || encoded;
    sequence_value := sequence_value / 36;
  end loop;
  candidate := 'u' || lpad(encoded, 7, '0');

  if not exists (
    select 1 from public.profiles where lower(username) = candidate
  ) then
    return candidate;
  end if;

  for batch in 1..512 loop
    -- Reserve tickets once; never rewind the sequence or reuse batch gaps.
    with tickets as materialized (
      select nextval('public.username_sequence'::regclass) as number
      from generate_series(1, 128)
    ), candidates as materialized (
      -- Same seven base36 digits as generated_username_for_number. Keep this
      -- expression here instead of invoking the search_path-pinned formatter.
      -- Regression tests compare both encodings at every digit boundary.
      select number, case when number between 1 and 78364164095 then
          'u'
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 2176782336 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 60466176 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 1679616 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 46656 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 1296 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number / 36 % 36)::integer + 1, 1)
          || substr('0123456789abcdefghijklmnopqrstuvwxyz', (number % 36)::integer + 1, 1)
        end as username
      from tickets
    )
    select available.username into candidate
    from candidates available
    where available.username is not null
      -- Keep unique-index probes rather than a full-profile hash anti-join.
      and (
        select true
        from public.profiles profile
        where lower(profile.username) = available.username
        limit 1
      ) is null
    order by available.number
    limit 1;

    if candidate is not null then
      return candidate;
    end if;

    if currval('public.username_sequence'::regclass) > 78364164095 then
      raise exception 'Generated username sequence is exhausted';
    end if;
  end loop;

  raise exception using errcode = '54000', message = 'username_allocation_busy';
end;
$$;

-- CREATE OR REPLACE preserves existing permissions; state the contract
-- explicitly without exposing either function to anonymous callers.
revoke all on function private.generated_username_for_number(bigint)
  from public, anon, authenticated;
revoke all on function private.generate_unique_username_impl() from public, anon;
grant execute on function private.generate_unique_username_impl()
  to authenticated, service_role;
