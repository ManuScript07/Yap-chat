import 'feed_formatting.dart';
import 'feed_post.dart';

// Match the network projection so disk and RPC data share the same decoder.
// Delivery receipts and exact coordinates are scoped to the live projection.
Map<String, Object?> encodeFeedPostSnapshot(FeedPost post) => {
  'id': post.id,
  'author_id': post.authorId,
  'author': {
    'display_name': post.authorName,
    'username': post.username,
    'avatar_url': post.avatarUrl,
    'avatar_storage_path': post.avatarPath,
    'avatar_updated_at': post.avatarRevision,
  },
  'text': post.text,
  'formatting': {
    'version': 1,
    'spans': [
      for (final span in post.formatting)
        {'start': span.start, 'end': span.end, 'style': span.style.name},
    ],
  },
  'created_at': post.createdAt.toIso8601String(),
  'edited': post.edited,
  'view_count': post.viewCount,
  'comment_count': post.commentCount,
  'comment_count_revision': post.commentCountRevision,
  'repost_count': post.repostCount,
  'action_version': post.reaction.version,
  'liked': post.reaction.liked,
  'like_count': post.reaction.likes,
  if (post.follow case final follow?)
    'author_relationship': {
      'version': follow.version,
      'following': follow.following,
      'can_follow': follow.canFollow,
    },
  if (post.nearby) 'location': {'nearby': true},
  'audience': post.friendsOnly ? 'friends' : 'public',
  'is_repost': post.isQuote,
  if (post.original case final original?)
    'original': encodeFeedPostSnapshot(original),
  if (post.repostedBy case final username?)
    'reposted_by': [
      {'username': username},
    ],
  if (post.reposted) 'my_repost': true,
  'photos': [
    for (final photo in post.photos)
      {
        'id': photo.id,
        'thumbnail_path': photo.thumbnailPath,
        'path': photo.path,
        'width': photo.width,
        'height': photo.height,
      },
  ],
};

FeedFollowState decodeFeedFollowState(Map<String, dynamic> row) => (
  version: row['version'] as int,
  following: row['following'] as bool,
  canFollow: row['can_follow'] as bool,
);

FeedPost decodeFeedPost(
  Map<String, dynamic> row, {
  FeedDelivery? delivery,
  int depth = 0,
}) {
  final author = row['author'] as Map<String, dynamic>?;
  final displayName = (author?['display_name'] as String?)?.trim();
  final text = row['text'] as String;
  final location = row['location'] as Map<String, dynamic>?;
  final latitude = (location?['latitude'] as num?)?.toDouble();
  final longitude = (location?['longitude'] as num?)?.toDouble();
  final follow = row['author_relationship'] as Map<String, dynamic>?;
  final original = row['original'] as Map<String, dynamic>?;
  final reposts = row['reposted_by'] as List<dynamic>?;
  return FeedPost(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: displayName == null || displayName.isEmpty
        ? (author?['username'] as String?)
        : displayName,
    username: author?['username'] as String?,
    avatarUrl: author?['avatar_url'] as String?,
    avatarPath: author?['avatar_storage_path'] as String?,
    avatarRevision: author?['avatar_updated_at'] as String?,
    text: text,
    formatting: decodeFeedFormatting(text, row['formatting']),
    createdAt: DateTime.parse(row['created_at'] as String),
    edited: row['edited'] == true,
    viewCount: row['view_count'] as int? ?? 0,
    commentCount: row['comment_count'] as int? ?? 0,
    commentCountRevision: row['comment_count_revision'] as int?,
    repostCount: row['repost_count'] as int? ?? 0,
    reaction: (
      version: row['action_version'] as int? ?? 0,
      liked: row['liked'] == true,
      likes: row['like_count'] as int? ?? 0,
    ),
    follow: follow == null ? null : decodeFeedFollowState(follow),
    delivery: delivery,
    coordinates: latitude == null || longitude == null
        ? null
        : (latitude: latitude, longitude: longitude),
    nearby: location?['nearby'] == true,
    friendsOnly: row['audience'] == 'friends',
    isQuote: row['is_repost'] == true,
    original: original == null || depth >= 4
        ? null
        : decodeFeedPost(original, depth: depth + 1),
    repostedBy: reposts?.firstOrNull?['username'] as String?,
    reposted: row['my_repost'] != null,
    photos: List.unmodifiable(
      (row['photos'] as List<dynamic>).map(
        (photo) => FeedPhoto(
          id: photo['id'] as String,
          thumbnailPath: photo['thumbnail_path'] as String,
          path: photo['path'] as String?,
          width: photo['width'] as int?,
          height: photo['height'] as int?,
        ),
      ),
    ),
  );
}
