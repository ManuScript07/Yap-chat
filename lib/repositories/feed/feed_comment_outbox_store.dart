import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';

import 'feed_post.dart';
import 'feed_comment_projection.dart';
import 'feed_post_snapshot_store.dart';

enum FeedCommentFailure {
  rejected,
  postUnavailable,
  replyUnavailable,
  exhausted,
}

typedef FeedCommentDelivery = ({
  AccountSessionSnapshot account,
  String postId,
  FeedCommentCreation? receipt,
  FeedCommentFailure? failure,
});

class FeedCommentOutboxEntry {
  FeedCommentOutboxEntry._(FeedCommentOperation row)
    : id = row.id,
      text = row.body,
      rootId = row.rootId,
      createdAt = _fromMicros(row.createdAt),
      failure = FeedCommentFailure.values.asNameMap()[row.failure],
      confirmedAt = row.confirmedAt == null
          ? null
          : _fromMicros(row.confirmedAt!),
      receipt = row.receipt == null ? null : _decodeReceipt(row.receipt!);

  final String id, text;
  final String? rootId;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final FeedCommentFailure? failure;
  final FeedCommentCreation? receipt;

  FeedComment pendingComment(String userId) => FeedComment(
    id: id,
    rootId: rootId,
    authorId: userId,
    text: text,
    createdAt: createdAt,
  );
}

class FeedCommentOutboxFull implements Exception {
  const FeedCommentOutboxFull();
}

class FeedCommentOutboxStore {
  FeedCommentOutboxStore(this._db, this._accounts, this._snapshots);

  static const _queueLimit = 100;
  static const _receiptLimit = 100;
  static const _receiptLifetime = Duration(minutes: 5);

  final AppDatabase _db;
  final AccountSessionController _accounts;
  final FeedPostSnapshotStore _snapshots;
  $FeedCommentOperationsTable get _table => _db.feedCommentOperations;

  Stream<List<FeedCommentOutboxEntry>> watch(
    AccountSessionSnapshot account,
    String postId,
    DateTime Function() now,
  ) {
    final query = _db.select(_table)
      ..where(
        (row) =>
            row.ownerUserId.equals(account.userId) & row.postId.equals(postId),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query
        .watch()
        .map<List<FeedCommentOutboxEntry>>((rows) {
          if (!_accounts.isCurrent(account)) return const [];
          final oldest = now()
              .subtract(_receiptLifetime)
              .microsecondsSinceEpoch;
          return [
            for (final row in rows)
              if (row.confirmedAt == null || row.confirmedAt! > oldest)
                FeedCommentOutboxEntry._(row),
          ];
        })
        .distinct(
          (previous, next) =>
              previous.length == next.length &&
              previous.indexed.every((item) {
                final (index, entry) = item;
                final updated = next[index];
                return entry.id == updated.id &&
                    entry.confirmedAt == updated.confirmedAt &&
                    entry.failure == updated.failure;
              }),
        );
  }

  Future<void> enqueue(
    AccountSessionSnapshot account,
    String postId,
    String id,
    String text,
    DateTime now, {
    required String? replyTo,
    required String? rootId,
  }) => _accounts.commit(
    account,
    () => _db.transaction(() async {
      final count = _table.id.count();
      final rows =
          await (_db.selectOnly(_table)
                ..addColumns([count])
                ..where(
                  _table.ownerUserId.equals(account.userId) &
                      _table.confirmedAt.isNull(),
                ))
              .getSingle();
      if (rows.read(count)! >= _queueLimit) throw const FeedCommentOutboxFull();
      _accounts.ensureCurrent(account);
      await _db
          .into(_table)
          .insert(
            FeedCommentOperationsCompanion.insert(
              ownerUserId: account.userId,
              id: id,
              postId: postId,
              body: text,
              replyToId: Value(replyTo),
              rootId: Value(rootId),
              createdAt: now.microsecondsSinceEpoch,
              nextAttemptAt: Value(now.microsecondsSinceEpoch),
            ),
          );
    }),
  );

  Future<FeedCommentOperation?> next(String owner) =>
      (_db.select(_table)
            ..where(
              (row) =>
                  row.ownerUserId.equals(owner) & row.nextAttemptAt.isNotNull(),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.nextAttemptAt),
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<int?> rateLimitedUntil(String owner, DateTime now) async {
    final until = _table.rateLimitedUntil.max();
    final result =
        await (_db.selectOnly(_table)
              ..addColumns([until])
              ..where(
                _table.ownerUserId.equals(owner) &
                    _table.rateLimitedUntil.isBiggerThanValue(
                      now.microsecondsSinceEpoch,
                    ),
              ))
            .getSingle();
    return result.read(until);
  }

  // Keep the UUID and a future wake-up durable before making a request. A crash
  // after dispatch can then replay without hammering the RPC on each launch.
  Future<void> defer(
    AccountSessionSnapshot account,
    String id, {
    required int attempts,
    required DateTime? next,
    DateTime? rateLimitedUntil,
    FeedCommentFailure? failure,
    String? unavailablePostId,
  }) => _accounts.commit(account, () async {
    Future<int> update() =>
        (_db.update(_table)..where((row) => _owned(row, account, id))).write(
          FeedCommentOperationsCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(next?.microsecondsSinceEpoch),
            rateLimitedUntil: Value(rateLimitedUntil?.microsecondsSinceEpoch),
            failure: Value(failure?.name),
          ),
        );
    if (unavailablePostId == null) {
      await update();
    } else {
      await _db.transaction(() async {
        await update();
        await _snapshots.evictOutboxPost(account.userId, unavailablePostId);
      });
    }
  });

  Future<void> acknowledge(
    AccountSessionSnapshot account,
    FeedCommentOperation operation,
    FeedCommentCreation receipt,
    DateTime now,
  ) => _accounts.commit(
    account,
    () => _db.transaction(() async {
      if (receipt.postCount case final count?) {
        await _snapshots.recordOutboxCount(
          account.userId,
          operation.postId,
          count,
        );
      }
      final owner = _table.ownerUserId.equals(account.userId);
      await (_db.update(
        _table,
      )..where((row) => _owned(row, account, operation.id))).write(
        FeedCommentOperationsCompanion(
          nextAttemptAt: const Value(null),
          failure: const Value(null),
          receipt: Value(
            jsonEncode({
              'comment': encodeFeedComment(receipt.comment),
              if (receipt.postCount case final count?) ...{
                'count': count.count,
                'revision': count.revision,
              },
            }),
          ),
          confirmedAt: Value(now.microsecondsSinceEpoch),
        ),
      );
      final newest = _db.selectOnly(_table)
        ..addColumns([_table.id])
        ..where(
          owner &
              _table.confirmedAt.isBiggerThanValue(
                now.subtract(_receiptLifetime).microsecondsSinceEpoch,
              ),
        )
        ..orderBy([
          OrderingTerm.desc(_table.confirmedAt),
          OrderingTerm.desc(_table.id),
        ])
        ..limit(_receiptLimit);
      await (_db.delete(_table)..where(
            (row) =>
                owner &
                row.confirmedAt.isNotNull() &
                row.id.isNotInQuery(newest),
          ))
          .go();
    }),
  );

  Future<void> discardFailed(AccountSessionSnapshot account, String id) =>
      _accounts.commit(account, () async {
        await (_db.delete(_table)..where(
              (row) => _owned(row, account, id) & row.failure.isNotNull(),
            ))
            .go();
      });

  Future<void> clearUser(String userId) async {
    await (_db.delete(
      _table,
    )..where((row) => row.ownerUserId.equals(userId))).go();
  }

  Expression<bool> _owned(
    $FeedCommentOperationsTable row,
    AccountSessionSnapshot account,
    String id,
  ) => row.ownerUserId.equals(account.userId) & row.id.equals(id);
}

DateTime _fromMicros(int value) =>
    DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);

FeedCommentCreation? _decodeReceipt(String payload) {
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final comment = decodeFeedComment(json['comment'] as Map<String, dynamic>);
    final count = json['count'];
    final revision = json['revision'];
    return (
      comment: comment,
      postCount: count is int && revision is int
          ? (count: count, revision: revision)
          : null,
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
