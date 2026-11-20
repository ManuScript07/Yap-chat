import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/blocks/blocks.dart';

import 'feed_comment_projection.dart';
import 'feed_post.dart';
import 'feed_post_projection.dart';

typedef FeedPostSnapshot = ({FeedPost post, DateTime expiresAt});
typedef FeedCommentCacheKey = (String, FeedCommentSort, String?);
typedef CachedFeedComments = ({FeedCommentsPage page, DateTime expiresAt});
typedef FeedCommentPageUpdate =
    FeedCommentsPage Function(FeedCommentCacheKey key, FeedCommentsPage page);

/// Stores confirmed details in the application's environment-specific database.
class FeedPostSnapshotStore {
  FeedPostSnapshotStore(
    this._database,
    this._accounts, {
    this._blocklist,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const maximumPosts = 16;
  static const maximumCommentPages = 24;
  static const maximumComments = 1200;
  final AppDatabase _database;
  final AccountSessionController _accounts;
  final BlocklistCacheDataSource? _blocklist;
  final DateTime Function() _now;

  Future<FeedPostSnapshot?> read(
    AccountSessionSnapshot account,
    String id,
  ) async => (await _readAccessible(account, id))?.$1;

  Future<(FeedPostSnapshot, Set<String>)?> _readAccessible(
    AccountSessionSnapshot account,
    String id,
  ) async {
    if (!_accounts.isCurrent(account)) return null;
    final row =
        await (_database.select(_database.cachedFeedPostSnapshots)..where(
              (row) =>
                  row.ownerUserId.equals(account.userId) &
                  row.postId.equals(id) &
                  row.expiresAtMicros.isBiggerThanValue(
                    _now().microsecondsSinceEpoch,
                  ),
            ))
            .getSingleOrNull();
    if (row == null || !_accounts.isCurrent(account)) return null;
    final post = _decode(row);
    if (post == null) return null;
    final blocked = await _blocklist?.read(account.userId);
    final expiresAt = DateTime.fromMicrosecondsSinceEpoch(
      row.expiresAtMicros,
      isUtc: true,
    );
    if (!_accounts.isCurrent(account) || !_now().isBefore(expiresAt)) {
      return null;
    }
    final blockedIds =
        blocked?.users.map((user) => user.id).toSet() ?? const <String>{};
    if (blockedIds.isNotEmpty) {
      for (FeedPost? item = post; item != null; item = item.original) {
        if (blockedIds.contains(item.authorId)) return null;
      }
    }
    return ((post: post, expiresAt: expiresAt), blockedIds);
  }

  Future<void> write(
    AccountSessionSnapshot account,
    FeedPostSnapshot snapshot, {
    required bool Function() allowed,
  }) => _accounts.commit(account, () async {
    final now = _now();
    if (!allowed() || !now.isBefore(snapshot.expiresAt)) return;
    final table = _database.cachedFeedPostSnapshots;
    await _database.transaction(() async {
      final expired =
          await (_database.selectOnly(table)
                ..addColumns([table.postId])
                ..where(
                  table.ownerUserId.equals(account.userId) &
                      table.postId.equals(snapshot.post.id).not() &
                      table.expiresAtMicros.isSmallerOrEqualValue(
                        now.microsecondsSinceEpoch,
                      ),
                ))
              .map((row) => row.read(table.postId)!)
              .get();
      await _remove(account.userId, expired);
      final previous = await _postRow(account.userId, snapshot.post.id);
      final saved = previous == null ? null : _postPayload(previous);
      final payload = encodeFeedPostSnapshot(snapshot.post);
      final savedRevision = saved?['comment_count_revision'];
      final savedCount = saved?['comment_count'];
      if (savedRevision is int && savedCount is int) {
        _applyPostCount(payload, (count: savedCount, revision: savedRevision));
      }
      await _database
          .into(table)
          .insertOnConflictUpdate(
            CachedFeedPostSnapshotsCompanion.insert(
              ownerUserId: account.userId,
              postId: snapshot.post.id,
              payload: jsonEncode(payload),
              expiresAtMicros: snapshot.expiresAt.microsecondsSinceEpoch,
            ),
          );
      final overflow =
          await (_database.selectOnly(table)
                ..addColumns([table.postId])
                ..where(table.ownerUserId.equals(account.userId))
                ..orderBy([
                  OrderingTerm.desc(table.expiresAtMicros),
                  OrderingTerm.asc(table.postId),
                ])
                ..limit(-1, offset: maximumPosts))
              .map((row) => row.read(table.postId)!)
              .get();
      await _remove(account.userId, overflow);
    });
  });

  Future<void> remove(AccountSessionSnapshot account, String id) =>
      removeUnavailable(account, (post) => !post.containsPost(id));

  Future<Map<FeedCommentCacheKey, CachedFeedComments>> readComments(
    AccountSessionSnapshot account,
    String id,
  ) async {
    final access = await _readAccessible(account, id);
    if (access == null) return {};
    final (post, blockedIds) = access;
    final rows = await _commentRows(account.userId, id);
    final now = _now();
    if (!_accounts.isCurrent(account) || !now.isBefore(post.expiresAt)) {
      return {};
    }
    final result = <FeedCommentCacheKey, CachedFeedComments>{};
    for (final row in rows) {
      final entry = _decodeCommentPage(row);
      if (entry == null || !now.isBefore(entry.expiresAt)) continue;
      final page = blockedIds.isEmpty
          ? entry.page
          : redactFeedCommentPage(entry.page, authors: blockedIds);
      result[_commentKey(row)] = (page: page, expiresAt: entry.expiresAt);
    }
    return result;
  }

  Future<void> writeCommentPage(
    AccountSessionSnapshot account,
    FeedCommentCacheKey key,
    CachedFeedComments snapshot, {
    required bool Function() allowed,
  }) => _accounts.commit(account, () async {
    final now = _now();
    if (!allowed() ||
        !now.isBefore(snapshot.expiresAt) ||
        snapshot.page.comments.length > maximumComments) {
      return;
    }
    final (postId, sort, root) = key;
    await _database.transaction(() async {
      final parent =
          await (_database.selectOnly(_database.cachedFeedPostSnapshots)
                ..addColumns([_database.cachedFeedPostSnapshots.postId])
                ..where(
                  _database.cachedFeedPostSnapshots.ownerUserId.equals(
                        account.userId,
                      ) &
                      _database.cachedFeedPostSnapshots.postId.equals(postId) &
                      _database.cachedFeedPostSnapshots.expiresAtMicros
                          .isBiggerThanValue(now.microsecondsSinceEpoch),
                ))
              .getSingleOrNull();
      if (parent == null || !allowed()) return;
      final table = _database.cachedFeedCommentSnapshots;
      await _database
          .into(table)
          .insertOnConflictUpdate(
            CachedFeedCommentSnapshotsCompanion.insert(
              ownerUserId: account.userId,
              postId: postId,
              sort: sort.name,
              rootId: root ?? '',
              payload: _encodeCommentPage(snapshot.page),
              rowCount: snapshot.page.comments.length,
              expiresAtMicros: snapshot.expiresAt.microsecondsSinceEpoch,
            ),
          );
      await _pruneCommentPages(account.userId, now);
    });
  });

  Future<void> updateCommentPages(
    AccountSessionSnapshot account,
    FeedCommentPageUpdate update, {
    String? postId,
    FeedCommentCount? postCount,
  }) => _accounts.commit(account, () async {
    await _database.transaction(() async {
      if (postId != null && postCount != null) {
        await _updatePostCount(account.userId, postId, postCount);
      }
      final rows = await _commentRows(account.userId, postId);
      final table = _database.cachedFeedCommentSnapshots;
      var grew = false;
      for (final row in rows) {
        final cached = _decodeCommentPage(row);
        if (cached == null) continue;
        final updated = update(_commentKey(row), cached.page);
        if (identical(updated.comments, cached.page.comments)) continue;
        if (updated.comments.length > maximumComments) continue;
        grew |= updated.comments.length > cached.page.comments.length;
        await (_database.update(table)..where(
              (item) =>
                  item.ownerUserId.equals(account.userId) &
                  item.postId.equals(row.postId) &
                  item.sort.equals(row.sort) &
                  item.rootId.equals(row.rootId),
            ))
            .write(
              CachedFeedCommentSnapshotsCompanion(
                payload: Value(_encodeCommentPage(updated)),
                rowCount: Value(updated.comments.length),
              ),
            );
      }
      if (grew) await _pruneCommentPages(account.userId, _now());
    });
  });

  // The outbox calls this within its account-scoped SQLite transaction.
  Future<void> recordOutboxCount(
    String userId,
    String postId,
    FeedCommentCount count,
  ) => _updatePostCount(userId, postId, count);

  Future<void> evictOutboxPost(String userId, String postId) =>
      _remove(userId, [postId]);

  Future<CachedFeedPostSnapshot?> _postRow(String userId, String id) =>
      (_database.select(_database.cachedFeedPostSnapshots)..where(
            (row) => row.ownerUserId.equals(userId) & row.postId.equals(id),
          ))
          .getSingleOrNull();

  Future<void> _updatePostCount(
    String userId,
    String id,
    FeedCommentCount count,
  ) async {
    final row = await _postRow(userId, id);
    if (row == null) return;
    final body = _postPayload(row);
    if (body == null || !_applyPostCount(body, count)) return;
    await (_database.update(_database.cachedFeedPostSnapshots)..where(
          (row) => row.ownerUserId.equals(userId) & row.postId.equals(id),
        ))
        .write(
          CachedFeedPostSnapshotsCompanion(payload: Value(jsonEncode(body))),
        );
  }

  bool _applyPostCount(Map<String, Object?> payload, FeedCommentCount count) {
    final previous = payload['comment_count_revision'];
    if (count.count < 0 ||
        count.revision <= (previous is int ? previous : -1)) {
      return false;
    }
    payload['comment_count'] = count.count;
    payload['comment_count_revision'] = count.revision;
    return true;
  }

  Future<List<CachedFeedCommentSnapshot>> _commentRows(
    String userId,
    String? postId,
  ) {
    final table = _database.cachedFeedCommentSnapshots;
    return (_database.select(table)..where(
          (row) =>
              row.ownerUserId.equals(userId) &
              (postId == null
                  ? const Constant(true)
                  : row.postId.equals(postId)),
        ))
        .get();
  }

  Future<void> _pruneCommentPages(String userId, DateTime now) async {
    final table = _database.cachedFeedCommentSnapshots;
    final rows =
        await (_database.selectOnly(table)
              ..addColumns([
                table.postId,
                table.sort,
                table.rootId,
                table.rowCount,
                table.expiresAtMicros,
              ])
              ..where(table.ownerUserId.equals(userId))
              ..orderBy([
                OrderingTerm.desc(table.expiresAtMicros),
                OrderingTerm.asc(table.postId),
                OrderingTerm.asc(table.sort),
                OrderingTerm.asc(table.rootId),
              ]))
            .get();
    var pageCount = 0;
    var rowCount = 0;
    final minimum = now.microsecondsSinceEpoch;
    await _database.batch((batch) {
      for (final row in rows) {
        final count = row.read(table.rowCount)!;
        if (pageCount < maximumCommentPages &&
            rowCount + count <= maximumComments &&
            row.read(table.expiresAtMicros)! > minimum) {
          pageCount++;
          rowCount += count;
          continue;
        }
        batch.deleteWhere(
          table,
          (item) =>
              item.ownerUserId.equals(userId) &
              item.postId.equals(row.read(table.postId)!) &
              item.sort.equals(row.read(table.sort)!) &
              item.rootId.equals(row.read(table.rootId)!),
        );
      }
    });
  }

  FeedCommentCacheKey _commentKey(CachedFeedCommentSnapshot row) => (
    row.postId,
    FeedCommentSort.values.byName(row.sort),
    row.rootId.isEmpty ? null : row.rootId,
  );

  String _encodeCommentPage(FeedCommentsPage page) => jsonEncode({
    'comments': [
      for (final comment in page.comments) encodeFeedComment(comment),
    ],
    if (page.next case final next?)
      'next': {'session': next.sessionId, 'position': next.position},
  });

  CachedFeedComments? _decodeCommentPage(CachedFeedCommentSnapshot row) {
    try {
      if (!FeedCommentSort.values.asNameMap().containsKey(row.sort)) {
        return null;
      }
      final json = jsonDecode(row.payload) as Map<String, dynamic>;
      final next = json['next'] as Map<String, dynamic>?;
      return (
        page: (
          comments: List.unmodifiable(
            (json['comments'] as List).map(
              (item) => decodeFeedComment(item as Map<String, dynamic>),
            ),
          ),
          next: next == null
              ? null
              : (
                  sessionId: next['session'] as String,
                  position: next['position'] as int,
                ),
        ),
        expiresAt: DateTime.fromMicrosecondsSinceEpoch(
          row.expiresAtMicros,
          isUtc: true,
        ),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> removeUnavailable(
    AccountSessionSnapshot account,
    bool Function(FeedPost) allowed,
  ) => _accounts.commit(account, () async {
    final rows = await (_database.select(
      _database.cachedFeedPostSnapshots,
    )..where((row) => row.ownerUserId.equals(account.userId))).get();
    final rejected = <String>[];
    for (final row in rows) {
      final post = _decode(row);
      if (post == null || !allowed(post)) rejected.add(row.postId);
    }
    await _remove(account.userId, rejected);
  });

  Future<void> _remove(String userId, List<String> posts) async {
    if (posts.isEmpty) return;
    await _database.transaction(() async {
      await (_database.delete(_database.cachedFeedCommentSnapshots)..where(
            (row) => row.ownerUserId.equals(userId) & row.postId.isIn(posts),
          ))
          .go();
      await (_database.delete(_database.cachedFeedPostSnapshots)..where(
            (row) => row.ownerUserId.equals(userId) & row.postId.isIn(posts),
          ))
          .go();
    });
  }

  Future<void> clearUser(String userId) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.cachedFeedCommentSnapshots,
      )..where((row) => row.ownerUserId.equals(userId))).go();
      await (_database.delete(
        _database.cachedFeedPostSnapshots,
      )..where((row) => row.ownerUserId.equals(userId))).go();
    });
  }

  FeedPost? _decode(CachedFeedPostSnapshot row) {
    try {
      final json = _postPayload(row);
      if (json == null) return null;
      final post = decodeFeedPost(json);
      return post.id == row.postId ? post : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Map<String, dynamic>? _postPayload(CachedFeedPostSnapshot row) {
    try {
      final value = jsonDecode(row.payload);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
