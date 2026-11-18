import 'package:yap_chat/repositories/feed/feed.dart';

typedef FeedCommentCacheKey = (String, FeedCommentSort, String?);
typedef CachedFeedPost = ({FeedPost post, DateTime expiresAt});
typedef CachedFeedComments = ({FeedCommentsPage page, DateTime expiresAt});

class FeedPublicationCache {
  FeedPublicationCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _ttl = Duration(minutes: 5);
  static const _maxRows = 1200;
  final DateTime Function() _now;
  final _entries = <FeedCommentCacheKey, CachedFeedComments>{};
  final _posts = <String, CachedFeedPost>{};
  int _rowCount = 0;

  DateTime expiresFromNow() => _now().add(_ttl);

  CachedFeedPost? readPost(String id) {
    final entry = _posts.remove(id);
    if (entry == null || !_now().isBefore(entry.expiresAt)) return null;
    _posts[id] = entry;
    return entry;
  }

  void writePost(FeedPost post) {
    _posts.remove(post.id);
    _posts[post.id] = (post: post, expiresAt: expiresFromNow());
    if (_posts.length > 16) removePost(_posts.keys.first);
  }

  CachedFeedComments? read(FeedCommentCacheKey key) {
    final entry = _remove(key);
    if (entry == null || !_now().isBefore(entry.expiresAt)) return null;
    _entries[key] = entry;
    _rowCount += entry.page.comments.length;
    return entry;
  }

  Map<FeedCommentCacheKey, CachedFeedComments> readForPost(String id) => {
    for (final key in _entries.keys.toList(growable: false))
      if (key.$1 == id) key: ?read(key),
  };

  void write(
    FeedCommentCacheKey key,
    FeedCommentsPage page, {
    required DateTime expiresAt,
  }) {
    _remove(key);
    if (page.comments.length > _maxRows || !_now().isBefore(expiresAt)) return;
    _entries[key] = (
      expiresAt: expiresAt,
      page: (comments: List.unmodifiable(page.comments), next: page.next),
    );
    _rowCount += page.comments.length;
    while (_entries.length > 24 || _rowCount > _maxRows) {
      _remove(_entries.keys.first);
    }
  }

  CachedFeedComments? _remove(FeedCommentCacheKey key) {
    final entry = _entries.remove(key);
    if (entry != null) _rowCount -= entry.page.comments.length;
    return entry;
  }

  void clear() {
    _entries.clear();
    _posts.clear();
    _rowCount = 0;
  }

  void removeComments(String id) {
    for (final key in _entries.keys.where((key) => key.$1 == id).toList()) {
      _remove(key);
    }
  }

  void removePost(String id) {
    _posts.remove(id);
    removeComments(id);
  }
}
