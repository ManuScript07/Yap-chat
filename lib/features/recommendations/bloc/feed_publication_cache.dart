import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

typedef FeedCommentCacheKey = (String, FeedCommentSort, String?);
typedef CachedFeedComments = ({FeedCommentsPage page, DateTime expiresAt});

class FeedPublicationCache {
  FeedPublicationCache({this.store, this.account, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _ttl = Duration(minutes: 5);
  static const _maxRows = 1200;
  final FeedPostSnapshotStore? store;
  final AccountSessionSnapshot? account;
  final DateTime Function() _now;
  final _entries = <FeedCommentCacheKey, CachedFeedComments>{};
  final _posts = <String, FeedPostSnapshot>{};
  Future<void>? _diskChanges;
  int _rowCount = 0;

  DateTime expiresFromNow() => _now().add(_ttl);

  FeedPostSnapshot? readPost(String id) {
    final entry = _posts.remove(id);
    if (entry == null || !_now().isBefore(entry.expiresAt)) return null;
    _posts[id] = entry;
    return entry;
  }

  Future<FeedPostSnapshot?> restorePost(String id) async {
    if (store == null || account == null) return null;
    try {
      await _diskChanges;
      return await store!.read(account!, id);
    } catch (_) {
      return null;
    }
  }

  void rememberPost(FeedPostSnapshot snapshot) {
    final id = snapshot.post.id;
    _posts.remove(id);
    _posts[id] = snapshot;
    if (_posts.length > FeedPostSnapshotStore.maximumPosts) {
      final oldest = _posts.keys.first;
      _posts.remove(oldest);
      removeComments(oldest);
    }
  }

  void writePost(FeedPost post, {required bool Function() allowed}) {
    final snapshot = (post: post, expiresAt: expiresFromNow());
    rememberPost(snapshot);
    _onDisk(
      (store, account) => store.write(account, snapshot, allowed: allowed),
    );
  }

  void removeUnavailablePosts(bool Function(FeedPost) allowed) {
    _onDisk((store, account) => store.removeUnavailable(account, allowed));
  }

  void _onDisk(
    Future<void> Function(FeedPostSnapshotStore, AccountSessionSnapshot) action,
  ) {
    final store = this.store;
    final account = this.account;
    if (store == null || account == null) return;
    // SQLite errors cannot change the result of a successful RPC.
    _diskChanges = action(store, account).catchError((Object _) {});
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
    removeComments(id);
    final affected = _posts.entries
        .where((entry) => entry.value.post.containsPost(id))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in affected) {
      _posts.remove(key);
      removeComments(key);
    }
    _onDisk((store, account) => store.remove(account, id));
  }
}
