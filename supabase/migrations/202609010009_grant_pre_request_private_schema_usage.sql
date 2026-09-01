-- The configured PostgREST authenticator resolves the pre-request function
-- through its schema, so it needs USAGE in addition to EXECUTE.
grant usage on schema private to authenticator;
