import 'package:yap_chat/repositories/feed/feed.dart';

typedef FeedCommentCacheKey = (String, FeedCommentSort, String?);

class FeedCommentCache {
  static const _ttl = Duration(minutes: 5);
  final _entries = <FeedCommentCacheKey, (DateTime, FeedCommentsPage)>{};

  FeedCommentsPage? read(FeedCommentCacheKey key) {
    final entry = _entries.remove(key);
    if (entry == null || DateTime.now().difference(entry.$1) >= _ttl) {
      return null;
    }
    _entries[key] = entry;
    return entry.$2;
  }

  void write(FeedCommentCacheKey key, FeedCommentsPage page) {
    _entries.remove(key);
    _entries[key] = (
      DateTime.now(),
      (comments: List.unmodifiable(page.comments), next: page.next),
    );
    if (_entries.length > 24) _entries.remove(_entries.keys.first);
  }

  void clear() => _entries.clear();

  void removePost(String id) => _entries.removeWhere((key, _) => key.$1 == id);
}
