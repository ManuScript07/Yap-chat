create sequence public.username_sequence
  as bigint
  start with 1
  increment by 1
  minvalue 1
  no maxvalue
  cache 1;

create or replace function public.generate_unique_username()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := '0123456789abcdefghijklmnopqrstuvwxyz';
  candidate text;
  encoded text;
  sequence_value bigint;
begin
  loop
    sequence_value := nextval('public.username_sequence'::regclass);
    encoded := '';

    while sequence_value > 0 loop
      encoded := substr(
        alphabet,
        (sequence_value % length(alphabet))::integer + 1,
        1
      ) || encoded;
      sequence_value := sequence_value / length(alphabet);
    end loop;

    if length(encoded) > 7 then
      raise exception 'Generated username sequence is exhausted';
    end if;

    candidate := 'u' || lpad(encoded, 7, '0');

    exit when not exists (
      select 1
      from public.profiles
      where lower(username) = candidate
    );
  end loop;

  return candidate;
end;
$$;

alter table public.profiles
  alter column username set default public.generate_unique_username();
