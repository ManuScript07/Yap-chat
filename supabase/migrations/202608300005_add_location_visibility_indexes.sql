-- The composite primary keys cover the owner/viewer lookup paths. These
-- indexes cover the reverse foreign-key paths used by profile deletion and by
-- future maintenance queries, satisfying the database advisor as well.
create index if not exists location_distance_read_limits_target_user_id_idx
  on private.location_distance_read_limits (target_user_id);

create index if not exists precise_location_exclusions_viewer_user_id_idx
  on private.precise_location_exclusions (viewer_user_id);
