-- Public RPCs stay SECURITY INVOKER so PostgREST exposes no callable
-- SECURITY DEFINER endpoint. The narrowly scoped implementations remain in
-- the private schema and enforce auth.uid() themselves.

create or replace function private.get_blocked_users_impl()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select profile.id, profile.username, profile.display_name,
    profile.avatar_url, profile.avatar_storage_path, block.created_at
  from public.user_blocks block
  join public.profiles profile on profile.id = block.blocked_user_id
  where block.blocker_user_id = auth.uid()
  order by block.created_at desc, profile.id;
$$;

create or replace function public.get_blocked_users()
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  created_at timestamptz
)
language sql stable security invoker set search_path = ''
as $$
  select * from private.get_blocked_users_impl();
$$;

create or replace function private.unblock_user_impl(target_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  delete from public.user_blocks
  where blocker_user_id = current_user_id and blocked_user_id = target_user_id;
  perform private.broadcast_block_change_impl(
    current_user_id,
    target_user_id,
    'unblocked'
  );
end;
$$;

create or replace function public.unblock_user(target_user_id uuid)
returns void
language sql security invoker set search_path = ''
as $$
  select private.unblock_user_impl(target_user_id);
$$;

revoke all on function private.get_blocked_users_impl()
  from public, anon, authenticated;
revoke all on function private.unblock_user_impl(uuid)
  from public, anon, authenticated;
revoke all on function public.get_blocked_users() from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function private.get_blocked_users_impl()
  to authenticated, service_role;
grant execute on function private.unblock_user_impl(uuid)
  to authenticated, service_role;
grant execute on function public.get_blocked_users() to authenticated, service_role;
grant execute on function public.unblock_user(uuid) to authenticated, service_role;
