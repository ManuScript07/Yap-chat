-- The primary key starts with profile_id, so it cannot support foreign-key
-- lookups or cascading deletes by viewer_id alone.
create index if not exists profile_view_daily_counters_viewer_id_idx
  on private.profile_view_daily_counters (viewer_id);
