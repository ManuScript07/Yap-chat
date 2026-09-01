-- get_my_account_access must produce one row even for an existing Auth user
-- whose profile setup has not completed yet.
create or replace function private.get_my_account_access_impl()
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
