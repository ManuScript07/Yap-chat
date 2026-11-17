import 'feed_formatting.dart';

typedef FeedDelivery = ({String id, DateTime expiresAt});
typedef FeedFollowState = ({int version, bool following, bool canFollow});
typedef FeedReaction = ({int version, bool liked, int likes});
typedef FeedCoordinates = ({double latitude, double longitude});

enum FeedPostAction { like, unlike, lessSimilar }

enum FeedReportReason { spam, scam, pornography, other }

class FeedPhoto {
  const FeedPhoto({
    required this.id,
    required this.thumbnailPath,
    this.path,
    this.width,
    this.height,
  });

  final String id;
  final String thumbnailPath;
  final String? path;
  final int? width;
  final int? height;

  double? get aspectRatio {
    final w = width;
    final h = height;
    return w != null && h != null && w > 0 && h > 0 ? w / h : null;
  }
}

typedef FeedComment = ({
  String id,
  String? authorId,
  String? authorName,
  String? text,
});

typedef FeedCommentsCursor = ({String sessionId, int position});
typedef FeedCommentsPage = ({
  List<FeedComment> comments,
  FeedCommentsCursor? next,
});

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.photos = const [],
    this.formatting = const [],
    this.username,
    this.avatarUrl,
    this.avatarPath,
    this.avatarRevision,
    this.edited = false,
    this.viewCount = 0,
    this.commentCount = 0,
    this.repostCount = 0,
    this.reaction = (version: 0, liked: false, likes: 0),
    this.follow,
    this.delivery,
    this.coordinates,
    this.nearby = false,
    this.isQuote = false,
    this.original,
    this.repostedBy,
    this.reposted = false,
  });

  final String id;
  final String authorId;
  final String? authorName;
  final String? username;
  final String? avatarUrl;
  final String? avatarPath;
  final String? avatarRevision;
  final String text;
  final DateTime createdAt;
  final List<FeedPhoto> photos;
  final List<FeedTextRange> formatting;
  final bool edited;
  final int viewCount;
  final int commentCount;
  final int repostCount;
  final FeedReaction reaction;
  final FeedFollowState? follow;
  final FeedDelivery? delivery;
  final FeedCoordinates? coordinates;
  final bool nearby;
  final bool isQuote;
  final FeedPost? original;
  final String? repostedBy;
  final bool reposted;
}
