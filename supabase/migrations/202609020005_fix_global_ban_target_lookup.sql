-- `target_user_id` was both the SQL-function argument and a column of the
-- joined bans table. In the predicate below PostgreSQL resolved it as the
-- column, making every non-null account appear banned while any active direct
-- ban existed. Positional parameter notation prevents that ambiguity.
create or replace function private.is_account_globally_banned(
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select $1 is not null and exists (
    select 1
    from private.global_ban_account_links link
    join private.global_account_bans ban on ban.id = link.ban_id
    where link.user_id = $1
      and ban.revoked_at is null
      and (ban.expires_at is null or ban.expires_at > now())
  );
$$;

revoke all on function private.is_account_globally_banned(uuid)
  from public, anon;
grant execute on function private.is_account_globally_banned(uuid)
  to authenticated, service_role;
