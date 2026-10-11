-- Keep the existing u + seven base-36 digits namespace. Sequence tickets are
-- never rewound: concurrent allocators may reserve different ranges safely.
create or replace function private.generated_username_for_number(value bigint)
returns text
language sql
immutable
parallel safe
-- SQL-standard body resolves functions/operators at definition time and can
-- be inlined. SET search_path would prevent inlining for every batch ticket.
-- CASE also returns NULL for NULL input. Do not mark STRICT: PostgreSQL cannot
-- prove CASE strictness for inlining, which would add one SQL call per ticket.
return case when value between 1 and 78364164095 then
    'u'
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 2176782336 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 60466176 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 1679616 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 46656 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 1296 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value / 36 % 36)::integer + 1, 1)
    || substr('0123456789abcdefghijklmnopqrstuvwxyz', (value % 36)::integer + 1, 1)
  end;

revoke all on function private.generated_username_for_number(bigint)
  from public, anon, authenticated;

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
  -- The ordinary, collision-free case still consumes just one ticket and
  -- performs one indexed lookup. Batching is only needed after a collision.
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
    -- Materialization evaluates nextval once per candidate. ORDER BY chooses
    -- the earliest free ticket even when PostgreSQL changes the join plan.
    -- Unused tickets in this reserved batch become harmless sequence gaps;
    -- setval/rewinding would let another allocator reuse an in-flight ticket.
    with tickets as materialized (
      select nextval('public.username_sequence'::regclass) as number
      from generate_series(1, 128)
    ), candidates as materialized (
      select number, private.generated_username_for_number(number) as username
      from tickets
    )
    select available.username into candidate
    from candidates available
    where available.username is not null
      -- A scalar, unique-index lookup prevents a hash anti-join from reading
      -- every profile for each batch. Only candidate index lookups are needed.
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

  -- Bound worst-case work under deliberately occupied ranges. Consumed
  -- sequence tickets survive rollback, so a later request moves past them.
  raise exception using errcode = '54000', message = 'username_allocation_busy';
end;
$$;

revoke all on function private.generate_unique_username_impl() from public, anon;
grant execute on function private.generate_unique_username_impl()
  to authenticated, service_role;

create or replace function private.handle_new_auth_user_impl()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  raw_birth_date text := coalesce(
    metadata ->> 'birth_date', metadata ->> 'birthdate', metadata ->> 'birthday'
  );
  verified_phone text := coalesce(
    nullif(new.phone::text, ''),
    nullif(metadata ->> 'phone', ''),
    nullif(metadata ->> 'phone_number', '')
  );
  lookup_hash bytea := private.phone_lookup_hash(verified_phone);
  conflict_constraint text;
  conflict_table text;
  conflict_schema text;
begin
  if lookup_hash is not null then
    update public.profiles
    set phone_lookup_hash = null
    where phone_lookup_hash = lookup_hash and id <> new.id;
  end if;

  for attempt in 1..8 loop
    begin
      insert into public.profiles (id, display_name, birth_date, avatar_url, phone_lookup_hash)
      values (
        new.id,
        coalesce(
          nullif(metadata ->> 'name', ''),
          nullif(metadata ->> 'real_name', ''),
          nullif(metadata ->> 'display_name', ''),
          ''
        ),
        case when raw_birth_date ~ '^[1-9][0-9]{3}-[0-9]{2}-[0-9]{2}$'
          then raw_birth_date::date else null end,
        coalesce(nullif(metadata ->> 'avatar_url', ''), nullif(metadata ->> 'picture', '')),
        lookup_hash
      )
      on conflict (id) do nothing;
      return new;
    exception when unique_violation then
      get stacked diagnostics
        conflict_constraint = constraint_name,
        conflict_table = table_name,
        conflict_schema = schema_name;
      -- Retry only a generated username race, never an unrelated uniqueness
      -- failure in phone mapping or in another trigger/table.
      if conflict_schema is distinct from 'public'
        or conflict_table is distinct from 'profiles'
        or conflict_constraint is distinct from 'profiles_username_lower_unique'
        or attempt = 8
      then
        raise;
      end if;
    end;
  end loop;
end;
$$;

revoke all on function private.handle_new_auth_user_impl()
  from public, anon, authenticated;

-- Keep the own-row RLS and all existing bootstrap/consent/avatar behavior.
create or replace function public.get_or_create_my_profile(
  p_display_name text default null,
  p_birth_date date default null,
  p_avatar_url text default null
)
returns setof public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  accepted_at timestamptz := now();
  active_terms_version text;
  active_privacy_policy_version text;
  conflict_constraint text;
  conflict_table text;
  conflict_schema text;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select legal.terms_version, legal.privacy_policy_version
  into active_terms_version, active_privacy_policy_version
  from private.get_active_legal_document_versions() legal;

  for attempt in 1..8 loop
    begin
      insert into public.profiles as profile (
        id, username, display_name, birth_date, avatar_url,
        terms_accepted_at, terms_version, privacy_accepted_at, privacy_policy_version
      )
      values (
        current_user_id,
        -- Do not allocate/discard another automatic name for an existing
        -- account at every sign-in. Re-read on retry if its name changed.
        coalesce(
          (select existing.username from public.profiles existing where existing.id = current_user_id),
          private.generate_unique_username_impl()
        ),
        coalesce(nullif(btrim(p_display_name), ''), ''),
        p_birth_date,
        nullif(btrim(p_avatar_url), ''),
        accepted_at,
        active_terms_version,
        accepted_at,
        active_privacy_policy_version
      )
      on conflict (id) do update
      set
        display_name = case
          when nullif(btrim(profile.display_name), '') is null then excluded.display_name
          else profile.display_name end,
        birth_date = coalesce(profile.birth_date, excluded.birth_date),
        avatar_url = case
          when not profile.yandex_avatar_disabled
            and profile.avatar_url is null and profile.avatar_storage_path is null
            then excluded.avatar_url
          else profile.avatar_url end,
        terms_accepted_at = coalesce(profile.terms_accepted_at, accepted_at),
        terms_version = case
          when profile.terms_accepted_at is null then active_terms_version
          else profile.terms_version end,
        privacy_accepted_at = coalesce(profile.privacy_accepted_at, accepted_at),
        privacy_policy_version = case
          when profile.privacy_accepted_at is null then active_privacy_policy_version
          else profile.privacy_policy_version end;
      exit;
    exception when unique_violation then
      get stacked diagnostics
        conflict_constraint = constraint_name,
        conflict_table = table_name,
        conflict_schema = schema_name;
      if conflict_schema is distinct from 'public'
        or conflict_table is distinct from 'profiles'
        or conflict_constraint is distinct from 'profiles_username_lower_unique'
        or attempt = 8
      then
        raise;
      end if;
    end;
  end loop;

  return query select profile.* from public.profiles profile where profile.id = current_user_id;
end;
$$;

comment on function private.generate_unique_username_impl() is
  'Allocates u + seven base36 digits. One lookup normally; indexed collision batches of 128, at most 512 batches. Username uniqueness is enforced at insertion.';
