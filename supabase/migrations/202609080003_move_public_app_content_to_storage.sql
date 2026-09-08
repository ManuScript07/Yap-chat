-- Public app metadata is a read-only Storage object, not a Data API RPC.
-- The existing private singleton remains the authoritative support-email
-- fallback for get_my_account_access on a freshly banned account.
update storage.buckets
set allowed_mime_types = array['application/pdf', 'application/json']
where id = 'legal-documents';

-- Removing this public SECURITY DEFINER RPC eliminates the advisor warning.
-- No mobile client uses it after this migration.
drop function if exists public.get_public_app_content();
drop function if exists private.get_public_app_content_impl();

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
  if request_path = 'rpc/get_my_account_access' then
    return;
  end if;
  perform private.require_active_account();
end;
$$;

notify pgrst, 'reload config';
