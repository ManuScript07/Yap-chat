-- Keep the account-link refresh parameter unambiguous inside PL/pgSQL. This
-- follows 007 so already applied environments receive the corrected trigger
-- body without rebuilding moderation tables.
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

revoke all on function private.refresh_global_ban_links_for_account(uuid)
  from public, anon, authenticated;
grant execute on function private.refresh_global_ban_links_for_account(uuid)
  to authenticated, service_role;
