import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

class FeedPublicationCache {
  FeedPublicationCache({this.store, this.account, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _ttl = Duration(minutes: 5);
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

  bool get hasDisk => store != null && account != null;

  Future<Map<FeedCommentCacheKey, CachedFeedComments>> restoreComments(
    String id,
  ) async {
    if (!hasDisk) return {};
    try {
      await _diskChanges;
      return await store!.readComments(account!, id);
    } catch (_) {
      return {};
    }
  }

  void write(
    FeedCommentCacheKey key,
    FeedCommentsPage page, {
    required DateTime expiresAt,
    required bool Function() allowed,
  }) {
    final snapshot = (
      expiresAt: expiresAt,
      page: (
        comments: List<FeedComment>.unmodifiable(page.comments),
        next: page.next,
      ),
    );
    rememberComments(key, snapshot);
    _onDisk(
      (store, account) =>
          store.writeCommentPage(account, key, snapshot, allowed: allowed),
    );
  }

  void rememberComments(FeedCommentCacheKey key, CachedFeedComments snapshot) {
    _remove(key);
    if (snapshot.page.comments.length > FeedPostSnapshotStore.maximumComments ||
        !_now().isBefore(snapshot.expiresAt)) {
      return;
    }
    _entries[key] = snapshot;
    _rowCount += snapshot.page.comments.length;
    while (_entries.length > FeedPostSnapshotStore.maximumCommentPages ||
        _rowCount > FeedPostSnapshotStore.maximumComments) {
      _remove(_entries.keys.first);
    }
  }

  void updateComments(
    FeedCommentPageUpdate update, {
    String? postId,
    FeedCommentCount? postCount,
  }) {
    for (final key in _entries.keys.toList(growable: false)) {
      if (postId != null && key.$1 != postId) continue;
      final entry = _entries[key];
      if (entry == null) continue;
      final page = update(key, entry.page);
      if (identical(page.comments, entry.page.comments)) continue;
      rememberComments(key, (page: page, expiresAt: entry.expiresAt));
    }
    _onDisk(
      (store, account) => store.updateCommentPages(
        account,
        update,
        postId: postId,
        postCount: postCount,
      ),
    );
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
