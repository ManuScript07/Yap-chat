-- PostgREST executes db-pre-request after switching from authenticator to the
-- request role. The guard must therefore be executable by every role that can
-- reach the Data API, including anonymous public-content reads.
grant execute on function private.enforce_data_api_account_access()
  to authenticator, anon, authenticated, service_role;
