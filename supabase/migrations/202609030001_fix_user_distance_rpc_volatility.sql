-- get_user_distance records an atomic per-viewer/target quota in its private
-- implementation. It therefore must remain VOLATILE: declaring the public
-- wrapper STABLE lets PostgREST execute it in a read-only transaction, where
-- the quota upsert fails before any distance can be returned.
create or replace function public.get_user_distance(target_user_id uuid)
returns table (distance_value integer, distance_unit text, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select *
  from private.get_user_distance_impl(target_user_id)
  where not private.is_account_globally_banned(target_user_id)
    and not private.is_blocked_by_impl(target_user_id, auth.uid());
$$;

revoke all on function public.get_user_distance(uuid) from public, anon;
grant execute on function public.get_user_distance(uuid) to authenticated, service_role;
