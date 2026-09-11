-- Cover the queue foreign keys. Besides satisfying the database linter, these
-- indexes avoid scans of the cleanup queue when Postgres validates a deletion
-- request or auth-user reference.

create index if not exists finalized_profile_media_cleanup_queue_deletion_request_idx
  on private.finalized_profile_media_cleanup_queue (deletion_request_id);

create index if not exists finalized_profile_media_cleanup_queue_owner_user_idx
  on private.finalized_profile_media_cleanup_queue (owner_user_id);
