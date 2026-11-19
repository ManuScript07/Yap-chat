import 'feed_post.dart';

Map<String, Object?> encodeFeedComment(
  FeedComment comment, {
  bool includePreview = true,
}) => {
  'id': comment.id,
  'root_id': comment.rootId,
  if (comment.authorId != null)
    'author': {
      'id': comment.authorId,
      'display_name': comment.authorName,
      'username': comment.username,
      'avatar_url': comment.avatarUrl,
      'avatar_storage_path': comment.avatarPath,
      'avatar_updated_at': comment.avatarRevision,
    },
  'text': comment.text,
  'created_at': comment.createdAt?.toIso8601String(),
  if (comment.replyTo case final target?)
    'reply_to': {
      'comment_id': target.id,
      'username': target.username,
      'user_id': target.userId,
    },
  if (includePreview && comment.replyPreview != null)
    'reply_preview': encodeFeedComment(
      comment.replyPreview!,
      includePreview: false,
    ),
  'reply_count': comment.replyCount,
  'version': comment.commentVersion,
  'post_version': comment.postVersion,
  'action_version': comment.reaction.version,
  'liked': comment.reaction.liked,
  'like_count': comment.reaction.likes,
};

FeedComment decodeFeedComment(
  Map<String, dynamic> row, {
  bool includePreview = true,
}) {
  final author = row['author'] as Map<String, dynamic>?;
  final target = row['reply_to'] as Map<String, dynamic>?;
  final preview = row['reply_preview'] as Map<String, dynamic>?;
  return FeedComment(
    id: row['id'] as String,
    rootId: row['root_id'] as String?,
    authorId: author?['id'] as String?,
    authorName: (author?['display_name'] ?? author?['username']) as String?,
    username: author?['username'] as String?,
    avatarUrl: author?['avatar_url'] as String?,
    avatarPath: author?['avatar_storage_path'] as String?,
    avatarRevision: author?['avatar_updated_at'] as String?,
    text: row['text'] as String?,
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    replyTo: target?['username'] is String && target?['comment_id'] is String
        ? (
            id: target!['comment_id'] as String,
            username: target['username'] as String,
            userId: target['user_id'] as String?,
          )
        : null,
    replyPreview: preview == null || !includePreview
        ? null
        : decodeFeedComment(preview, includePreview: false),
    replyCount: row['reply_count'] as int? ?? 0,
    commentVersion: row['version'] as int? ?? 0,
    postVersion: row['post_version'] as int? ?? 0,
    reaction: (
      version: row['action_version'] as int? ?? 0,
      liked: row['liked'] == true,
      likes: row['like_count'] as int? ?? 0,
    ),
  );
}
