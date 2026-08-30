-- Legal documents are public, versioned, read-only application assets.
-- Upload and replace files with the Supabase service role (or the dashboard);
-- the mobile client receives only the HTTPS URLs from get_public_app_content().
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'legal-documents',
  'legal-documents',
  true,
  10485760,
  array['application/pdf']
)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- No INSERT/UPDATE/DELETE policy is granted to app users. Public bucket
-- retrieval is intentionally the only client-facing operation.
