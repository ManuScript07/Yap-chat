-- The primary key covers lookups by viewer and target. A separate target-side
-- index lets PostgreSQL enforce the profile FK efficiently when a target
-- profile is deleted and its limiter rows cascade.
create index if not exists profile_friend_list_read_limits_target_user_id_idx
  on private.profile_friend_list_read_limits (target_user_id);
