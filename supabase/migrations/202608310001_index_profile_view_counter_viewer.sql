-- A primary key on (profile_id, viewer_id) serves profile aggregates but not
-- FK checks/cascades that start from viewer_id.
create index if not exists profile_view_counters_viewer_idx
  on private.profile_view_counters (viewer_id);
