import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/blocks/blocks.dart';

import 'feed_post.dart';
import 'feed_post_projection.dart';

typedef FeedPostSnapshot = ({FeedPost post, DateTime expiresAt});

/// Stores confirmed details in the application's environment-specific database.
class FeedPostSnapshotStore {
  FeedPostSnapshotStore(
    this._database,
    this._accounts, {
    this._blocklist,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const maximumPosts = 16;
  final AppDatabase _database;
  final AccountSessionController _accounts;
  final BlocklistCacheDataSource? _blocklist;
  final DateTime Function() _now;

  Future<FeedPostSnapshot?> read(
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
    if (blocked != null) {
      final ids = blocked.users.map((user) => user.id).toSet();
      for (FeedPost? item = post; item != null; item = item.original) {
        if (ids.contains(item.authorId)) return null;
      }
    }
    return (post: post, expiresAt: expiresAt);
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
      await (_database.delete(table)..where(
            (row) => row.expiresAtMicros.isSmallerOrEqualValue(
              now.microsecondsSinceEpoch,
            ),
          ))
          .go();
      await _database
          .into(table)
          .insertOnConflictUpdate(
            CachedFeedPostSnapshotsCompanion.insert(
              ownerUserId: account.userId,
              postId: snapshot.post.id,
              payload: jsonEncode(encodeFeedPostSnapshot(snapshot.post)),
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
    await (_database.delete(_database.cachedFeedPostSnapshots)..where(
          (row) => row.ownerUserId.equals(userId) & row.postId.isIn(posts),
        ))
        .go();
  }

  Future<void> clearUser(String userId) async {
    await (_database.delete(
      _database.cachedFeedPostSnapshots,
    )..where((row) => row.ownerUserId.equals(userId))).go();
  }

  FeedPost? _decode(CachedFeedPostSnapshot row) {
    try {
      final json = jsonDecode(row.payload) as Map<String, dynamic>;
      final post = decodeFeedPost(json);
      return post.id == row.postId ? post : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
