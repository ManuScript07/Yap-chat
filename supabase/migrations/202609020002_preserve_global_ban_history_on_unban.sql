-- A global unban is a reversible moderation action. Keep the original row so
-- moderator aggregates retain the complete count of bans issued over time.
alter table private.global_account_bans
  add column if not exists revoked_at timestamptz;

drop index private.global_account_bans_active_expiry_idx;
create index global_account_bans_active_expiry_idx
  on private.global_account_bans (expires_at)
  where revoked_at is null and expires_at is not null;

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
      and ban.revoked_at is null
      and (ban.expires_at is null or ban.expires_at > now())
  );
$$;

drop trigger global_account_bans_refresh_links
  on private.global_account_bans;
create trigger global_account_bans_refresh_links
after insert or update of target_user_id, expires_at, revoked_at
on private.global_account_bans
for each row execute function private.refresh_global_ban_links_after_change();

comment on column private.global_account_bans.revoked_at is
  'Set to now() to unban while preserving the historical moderation record.';
