-- Support foreign-key lookups when deleting a comment thread or profile.
create index feed_comments_root_post_idx on feed.comments (root_id, post_id);
create index hidden_authors_author_idx on recsys.hidden_authors (author_id);

-- Cover references to the embedding space independently of queue and vector indexes.
create index vision_embeddings_space_idx on recsys.vision_embeddings (space);
create index vision_jobs_space_idx on recsys.vision_jobs (space);
