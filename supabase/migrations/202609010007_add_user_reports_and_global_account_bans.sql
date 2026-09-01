-- Moderation is intentionally kept outside the public API schema. Clients can
-- submit a report through a narrow RPC, while operators inspect the private
-- tables/views in Supabase Studio.
create table private.global_account_bans (
  id uuid primary key default extensions.gen_random_uuid(),
  target_user_id uuid not null references auth.users(id) on delete restrict,
  yandex_subject text,
  email_lookup_hash bytea,
  phone_lookup_hash bytea,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  created_by text,
  note text,
  check (expires_at is null or expires_at > created_at)
);

create index global_account_bans_target_user_id_idx
  on private.global_account_bans (target_user_id, created_at desc);
create index global_account_bans_active_expiry_idx
  on private.global_account_bans (expires_at)
  where expires_at is not null;

create table private.global_ban_account_links (
  ban_id uuid not null references private.global_account_bans(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (ban_id, user_id)
);

create index global_ban_account_links_user_id_idx
  on private.global_ban_account_links (user_id, ban_id);

revoke all on table private.global_account_bans
  from public, anon, authenticated;
revoke all on table private.global_ban_account_links
  from public, anon, authenticated;

-- Reuse the existing private HMAC secret, but prefix the value by type so an
-- email digest cannot collide with a phone digest.
create or replace function private.email_lookup_hash(raw_email text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.hmac(
    pg_catalog.convert_to(
      'email:' || lower(btrim(raw_email)),
      'UTF8'
    ),
    secret.secret,
    'sha256'
  )
  from private.phone_lookup_secrets secret
  where secret.singleton
    and nullif(btrim(coalesce(raw_email, '')), '') is not null;
$$;

create or replace function private.yandex_subject_for_user(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    nullif(identity.identity_data ->> 'sub', ''),
    nullif(identity.identity_data ->> 'id', '')
  )
  from auth.identities identity
  where identity.user_id = target_user_id
    and identity.provider = 'custom:yandex'
  order by identity.last_sign_in_at desc nulls last, identity.id
  limit 1;
$$;

create or replace function private.capture_global_ban_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_email text;
begin
  select auth_user.email
  into target_email
  from auth.users auth_user
  where auth_user.id = new.target_user_id;

  if target_email is null and not exists (
    select 1 from auth.users auth_user where auth_user.id = new.target_user_id
  ) then
    raise exception using errcode = '23503', message = 'global_ban_target_not_found';
  end if;

  new.yandex_subject := private.yandex_subject_for_user(new.target_user_id);
  new.email_lookup_hash := private.email_lookup_hash(target_email);
  select profile.phone_lookup_hash
  into new.phone_lookup_hash
  from public.profiles profile
  where profile.id = new.target_user_id;
  return new;
end;
$$;

create or replace function private.refresh_global_ban_account_links(
  target_ban_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.global_ban_account_links
  where ban_id = target_ban_id;

  insert into private.global_ban_account_links (ban_id, user_id)
  select ban.id, candidate.id
  from private.global_account_bans ban
  join auth.users candidate on (
    candidate.id = ban.target_user_id
    or (
      ban.email_lookup_hash is not null
      and ban.email_lookup_hash = private.email_lookup_hash(candidate.email)
    )
    or exists (
      select 1
      from public.profiles candidate_profile
      where candidate_profile.id = candidate.id
        and ban.phone_lookup_hash is not null
        and candidate_profile.phone_lookup_hash = ban.phone_lookup_hash
    )
    or exists (
      select 1
      from auth.identities identity
      where identity.user_id = candidate.id
        and identity.provider = 'custom:yandex'
        and ban.yandex_subject is not null
        and coalesce(
          nullif(identity.identity_data ->> 'sub', ''),
          nullif(identity.identity_data ->> 'id', '')
        ) = ban.yandex_subject
    )
  )
  where ban.id = target_ban_id
  on conflict do nothing;
end;
$$;

create or replace function private.refresh_global_ban_links_for_account(
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_ban_id uuid;
begin
  for target_ban_id in
    select ban.id
    from private.global_account_bans ban
    where ban.target_user_id = $1
       or (
         ban.email_lookup_hash is not null
         and ban.email_lookup_hash = (
           select private.email_lookup_hash(auth_user.email)
           from auth.users auth_user
           where auth_user.id = $1
         )
       )
       or (
         ban.phone_lookup_hash is not null
         and ban.phone_lookup_hash = (
           select profile.phone_lookup_hash
           from public.profiles profile
           where profile.id = $1
         )
       )
       or (
         ban.yandex_subject is not null
         and ban.yandex_subject = private.yandex_subject_for_user($1)
       )
  loop
    perform private.refresh_global_ban_account_links(target_ban_id);
  end loop;
end;
$$;

create or replace function private.refresh_global_ban_links_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_global_ban_account_links(new.id);
  return new;
end;
$$;

create or replace function private.refresh_global_ban_links_after_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_global_ban_links_for_account(new.id);
  return new;
end;
$$;

create or replace function private.refresh_global_ban_links_after_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_global_ban_links_for_account(new.user_id);
  return new;
end;
$$;

create or replace function private.refresh_global_ban_links_after_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_global_ban_links_for_account(new.id);
  return new;
end;
$$;

create trigger global_account_bans_capture_identity
before insert or update of target_user_id
on private.global_account_bans
for each row execute function private.capture_global_ban_identity();

create trigger global_account_bans_refresh_links
after insert or update of target_user_id, expires_at
on private.global_account_bans
for each row execute function private.refresh_global_ban_links_after_change();

create trigger auth_users_refresh_global_ban_links
after insert or update of email
on auth.users
for each row execute function private.refresh_global_ban_links_after_auth_user();

create trigger auth_identities_refresh_global_ban_links
after insert or update of provider, identity_data
on auth.identities
for each row execute function private.refresh_global_ban_links_after_identity();

create trigger profiles_refresh_global_ban_links
after insert or update of phone_lookup_hash
on public.profiles
for each row execute function private.refresh_global_ban_links_after_profile();

-- Populate links for any user that already matches a newly deployed ban.
do $$
declare
  target_ban_id uuid;
begin
  for target_ban_id in select id from private.global_account_bans loop
    perform private.refresh_global_ban_account_links(target_ban_id);
  end loop;
end;
$$;

create or replace function private.is_account_globally_banned(
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and exists (
    select 1
    from private.global_ban_account_links link
    join private.global_account_bans ban on ban.id = link.ban_id
    where link.user_id = target_user_id
      and (ban.expires_at is null or ban.expires_at > now())
  );
$$;

create or replace function private.require_active_account()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if private.is_account_globally_banned(auth.uid()) then
    raise exception using errcode = 'P0001', message = 'account_globally_banned';
  end if;
end;
$$;

-- A narrow exception used only by AuthGate to render the access-restricted
-- page. It intentionally exposes neither a moderation reason nor ban dates.
create or replace function private.get_my_account_access_impl()
returns table (is_banned boolean, username text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  return query
  select private.is_account_globally_banned(account.user_id), profile.username
  from (select auth.uid() as user_id) account
  left join public.profiles profile on profile.id = account.user_id;
end;
$$;

create or replace function public.get_my_account_access()
returns table (is_banned boolean, username text)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_my_account_access_impl();
$$;

-- PostgREST executes this before each existing Data API request. It avoids
-- maintaining a second connection or duplicating a ban check across every
-- public RPC. Storage and Realtime are covered by restrictive policies below.
create or replace function private.enforce_data_api_account_access()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_path text := current_setting('request.path', true);
  request_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if request_role <> 'authenticated' then return; end if;
  if request_path in ('rpc/get_my_account_access', 'rpc/get_public_app_content') then
    return;
  end if;
  perform private.require_active_account();
end;
$$;

alter role authenticator
  set pgrst.db_pre_request = 'private.enforce_data_api_account_access';
notify pgrst, 'reload config';

revoke all on function private.email_lookup_hash(text)
  from public, anon, authenticated;
revoke all on function private.yandex_subject_for_user(uuid)
  from public, anon, authenticated;
revoke all on function private.capture_global_ban_identity()
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_account_links(uuid)
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_links_for_account(uuid)
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_links_after_change()
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_links_after_auth_user()
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_links_after_identity()
  from public, anon, authenticated;
revoke all on function private.refresh_global_ban_links_after_profile()
  from public, anon, authenticated;
revoke all on function private.is_account_globally_banned(uuid)
  from public, anon;
revoke all on function private.require_active_account()
  from public, anon;
revoke all on function private.get_my_account_access_impl()
  from public, anon;
revoke all on function private.enforce_data_api_account_access()
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_account_access()
  from public, anon;

grant execute on function private.is_account_globally_banned(uuid)
  to authenticated, service_role;
grant execute on function private.require_active_account()
  to authenticated, service_role;
grant execute on function private.get_my_account_access_impl()
  to authenticated, service_role;
grant execute on function private.enforce_data_api_account_access()
  to authenticator, anon, authenticated, service_role;
grant usage on schema private to authenticator;
grant execute on function public.get_my_account_access()
  to authenticated, service_role;

-- Restrictive policies are AND-ed with all existing policies. They cover
-- GraphQL/direct table access as well as future permissive policies without
-- changing the established relationship and visibility logic.
create policy "Globally banned accounts cannot access profiles"
on public.profiles
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access profile photos"
on public.profile_photos
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access blocks"
on public.user_blocks
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access conversations"
on public.conversations
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access conversation members"
on public.conversation_members
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access messages"
on public.messages
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access message attachments"
on public.message_attachments
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access message receipts"
on public.message_receipts
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access hidden messages"
on public.message_hidden_for_users
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access friendships"
on public.friendships
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access friend requests"
on public.friend_requests
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access locations"
on public.user_locations
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access push devices"
on public.push_devices
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot access storage"
on storage.objects
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create policy "Globally banned accounts cannot use realtime"
on realtime.messages
as restrictive for all to authenticated
using (not private.is_account_globally_banned((select auth.uid())))
with check (not private.is_account_globally_banned((select auth.uid())));

create table private.user_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  reporter_user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('spam', 'scam', 'pornography', 'other')),
  created_at timestamptz not null default now(),
  check (reporter_user_id <> target_user_id)
);

create index user_reports_target_created_idx
  on private.user_reports (target_user_id, created_at desc);
create index user_reports_reporter_target_created_idx
  on private.user_reports (reporter_user_id, target_user_id, created_at desc);
create index user_reports_reporter_created_idx
  on private.user_reports (reporter_user_id, created_at desc);

create table private.user_report_daily_limits (
  reporter_user_id uuid not null references public.profiles(id) on delete cascade,
  day_utc date not null,
  distinct_target_count integer not null default 0 check (distinct_target_count >= 0),
  primary key (reporter_user_id, day_utc)
);

revoke all on table private.user_reports from public, anon, authenticated;
revoke all on table private.user_report_daily_limits from public, anon, authenticated;

create or replace function private.submit_user_report_impl(
  p_target_user_id uuid,
  p_report_reason text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  report_created_at timestamptz;
  today_utc date := (now() at time zone 'UTC')::date;
  current_day_count integer;
begin
  perform private.require_active_account();
  if p_target_user_id is null or p_target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_report_target';
  end if;
  if p_report_reason not in ('spam', 'scam', 'pornography', 'other') then
    raise exception using errcode = '22023', message = 'invalid_report_reason';
  end if;
  if not exists (select 1 from public.profiles where id = p_target_user_id) then
    raise exception using errcode = 'P0002', message = 'report_target_not_found';
  end if;

  -- One advisory lock serializes all of a reporter's quota checks, including
  -- simultaneous attempts against different targets.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_user_id::text, 92173)
  );
  if exists (
    select 1
    from private.user_reports report
    where report.reporter_user_id = current_user_id
      and report.target_user_id = p_target_user_id
      and report.created_at > now() - interval '7 days'
  ) then
    raise exception using errcode = 'P0001', message = 'user_report_target_rate_limited';
  end if;

  insert into private.user_report_daily_limits as limit_row (
    reporter_user_id, day_utc, distinct_target_count
  ) values (current_user_id, today_utc, 0)
  on conflict (reporter_user_id, day_utc) do nothing;

  select limit_row.distinct_target_count
  into current_day_count
  from private.user_report_daily_limits limit_row
  where limit_row.reporter_user_id = current_user_id
    and limit_row.day_utc = today_utc
  for update;

  if current_day_count >= 5 then
    raise exception using errcode = 'P0001', message = 'user_report_daily_rate_limited';
  end if;

  insert into private.user_reports (
    reporter_user_id, target_user_id, reason
  ) values (
    current_user_id, p_target_user_id, p_report_reason
  ) returning created_at into report_created_at;

  update private.user_report_daily_limits limit_row
  set distinct_target_count = limit_row.distinct_target_count + 1
  where limit_row.reporter_user_id = current_user_id
    and limit_row.day_utc = today_utc;

  return report_created_at;
end;
$$;

create or replace function public.submit_user_report(
  target_user_id uuid,
  report_reason text
)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$
  select private.submit_user_report_impl(target_user_id, report_reason);
$$;

revoke all on function private.submit_user_report_impl(uuid, text)
  from public, anon;
revoke all on function public.submit_user_report(uuid, text)
  from public, anon;
grant execute on function private.submit_user_report_impl(uuid, text)
  to authenticated, service_role;
grant execute on function public.submit_user_report(uuid, text)
  to authenticated, service_role;

create or replace view private.moderation_user_reports as
select
  report.id,
  report.created_at,
  report.reason,
  report.reporter_user_id,
  reporter.username as reporter_username,
  reporter.display_name as reporter_display_name,
  report.target_user_id,
  target.username as target_username,
  target.display_name as target_display_name,
  count(*) over (partition by report.target_user_id)::integer as target_report_count,
  count(*) over (partition by report.reporter_user_id)::integer as reporter_report_count,
  (
    select count(*)::integer
    from public.user_blocks block
    where block.blocked_user_id = report.target_user_id
  ) as target_personal_block_count,
  (
    select count(*)::integer
    from private.global_account_bans ban
    where ban.target_user_id = report.target_user_id
  ) as target_global_ban_count
from private.user_reports report
join public.profiles reporter on reporter.id = report.reporter_user_id
join public.profiles target on target.id = report.target_user_id;

revoke all on private.moderation_user_reports from public, anon, authenticated;

comment on table private.global_account_bans is
  'Insert a target_user_id from auth.users in Supabase Studio. Identity snapshots and matching account links are maintained automatically.';
comment on view private.moderation_user_reports is
  'Operator-only report queue with reporter/target identity and moderation aggregates.';
