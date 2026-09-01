-- The account-access RPC already runs during login. Include the non-sensitive
-- support address there so a freshly installed, globally banned client can
-- render the restriction screen without waiting for a second public RPC.
drop function public.get_my_account_access();
drop function private.get_my_account_access_impl();

create function private.get_my_account_access_impl()
returns table (is_banned boolean, username text, support_email text)
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
  select
    private.is_account_globally_banned(account.user_id),
    profile.username,
    content.support_email
  from (select auth.uid() as user_id) account
  left join public.profiles profile on profile.id = account.user_id
  left join private.app_public_content content on content.singleton;
end;
$$;

create function public.get_my_account_access()
returns table (is_banned boolean, username text, support_email text)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_my_account_access_impl();
$$;

revoke all on function private.get_my_account_access_impl()
  from public, anon;
revoke all on function public.get_my_account_access()
  from public, anon;
grant execute on function private.get_my_account_access_impl()
  to authenticated, service_role;
grant execute on function public.get_my_account_access()
  to authenticated, service_role;
