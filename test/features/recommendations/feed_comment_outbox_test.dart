import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

const _postId = 'post';
const _popular = (_postId, FeedCommentSort.popular, null);
const _parent = FeedComment(id: 'parent', authorId: 'author', text: 'parent');

void main() {
  late AppDatabase db;
  late AccountSessionController accounts;
  late AccountSessionSnapshot account;
  late ValueNotifier<bool?> network;
  late FeedPostSnapshotStore snapshots;
  late FeedCommentOutbox outbox;
  late _Publication repository;
  late DateTime now;
  late FeedPost post;
  late Directory directory;
  late File file;

  void openDb() {
    db = AppDatabase.forTesting(NativeDatabase(file));
    snapshots = FeedPostSnapshotStore(db, accounts, now: () => now);
    outbox = FeedCommentOutbox(
      db,
      accounts,
      repository,
      network,
      snapshots,
      now: () => now,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yap-comments-outbox-');
    file = File('${directory.path}/local.sqlite');
    now = DateTime.now();
    accounts = AccountSessionController(initialUserId: 'viewer');
    account = accounts.capture();
    network = ValueNotifier<bool?>(false);
    repository = _Publication();
    post = FeedPost(
      id: _postId,
      authorId: 'author',
      authorName: 'author',
      text: 'post',
      createdAt: now,
    );
    openDb();
    await snapshots.write(account, (
      post: post,
      expiresAt: now.add(const Duration(minutes: 5)),
    ), allowed: () => true);
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
    network.dispose();
    await file.delete();
    await directory.delete();
  });

  Future<void> queue(String text) =>
      outbox.enqueue(account, _postId, text, replyTo: null, rootId: null);

  Future<FeedCommentOutboxEntry> entryWhere(
    bool Function(FeedCommentOutboxEntry) condition,
  ) async =>
      (await outbox
              .watch(account, _postId)
              .firstWhere((entries) => entries.any(condition)))
          .firstWhere(condition);

  void reachNetwork() {
    outbox.setAuthenticatedUser(accounts.userId);
    network.value = true;
  }

  test(
    'v32 migration preserves the saved post and adds both queue indexes',
    () async {
      await db.customStatement('DROP TABLE feed_comment_operations');
      await db.customStatement('PRAGMA user_version = 32');
      await outbox.dispose();
      await db.close();
      openDb();
      expect((await snapshots.read(account, _postId))?.post.id, _postId);
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'feed_comment_operations'",
          )
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        containsAll(['feed_comment_outbox_due', 'feed_comment_outbox_post']),
      );
      final planner = await db.customSelect('''
        EXPLAIN QUERY PLAN
        SELECT id FROM feed_comment_operations
        WHERE owner_user_id = 'viewer' AND next_attempt_at IS NOT NULL
        ORDER BY next_attempt_at, created_at, id LIMIT 1
      ''').get();
      expect(planner.map((row) => row.read<String>('detail')), [
        contains('feed_comment_outbox_due'),
      ]);
      await queue('after upgrade');
      expect((await entryWhere((_) => true)).text, 'after upgrade');
    },
  );

  test(
    'cold restart and lost response replay exactly one server row',
    () async {
      var loseReceipt = true;
      repository.send = (request) async {
        final result = repository.confirm(request);
        if (loseReceipt) {
          loseReceipt = false;
          throw TimeoutException('response lost');
        }
        return result;
      };
      await queue('survives restart');
      final original = await entryWhere((_) => true);
      expect(repository.requests, isEmpty);
      await outbox.dispose();
      await db.close();
      openDb();
      reachNetwork();
      await _until(
        () async =>
            repository.requests.length == 1 &&
            (await db.select(db.feedCommentOperations).getSingle()).attempts ==
                1,
      );
      await outbox.dispose();
      await db.close();
      expect(repository.saved, hasLength(1));
      now = now.add(const Duration(seconds: 20));
      openDb();
      reachNetwork();
      final delivered = await entryWhere((row) => row.receipt != null);
      expect(repository.requests.map((request) => request.id), [
        original.id,
        original.id,
      ]);
      expect(repository.saved, hasLength(1));
      expect(delivered.receipt!.postCount, (count: 1, revision: 1));
      expect((await snapshots.read(account, _postId))!.post.commentCount, 1);
    },
  );

  test('a SQLite failure rolls back both receipt and cached count', () async {
    await db.customStatement('''
      CREATE TRIGGER reject_receipt BEFORE UPDATE ON feed_comment_operations
      WHEN new.confirmed_at IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'test write failure'); END
    ''');
    await queue('atomic receipt');
    reachNetwork();
    await _until(() async => repository.requests.length == 1);
    await accounts.drainCommits();
    expect((await entryWhere((_) => true)).confirmedAt, isNull);
    expect((await snapshots.read(account, _postId))!.post.commentCount, 0);
    await db.customStatement('DROP TRIGGER reject_receipt');
    now = now.add(const Duration(seconds: 20));
    network.value = false;
    network.value = true;
    expect(
      (await entryWhere((row) => row.receipt != null)).receipt!.postCount,
      (count: 1, revision: 1),
    );
    expect(
      repository.requests.map((request) => request.id).toSet(),
      hasLength(1),
    );
  });

  test(
    'an access denial evicts the post and retains the author’s text',
    () async {
      repository.send = (_) async => throw const PostgrestException(
        code: 'PT404',
        message: 'post_not_found',
      );
      await queue('keep my text');
      reachNetwork();
      final failure = await entryWhere((row) => row.failure != null);
      expect(failure.failure, FeedCommentFailure.postUnavailable);
      expect(failure.text, 'keep my text');
      expect(await snapshots.read(account, _postId), isNull);
      network.value = false;
      network.value = true;
      await outbox.discardFailed(account, failure.id);
      expect(await outbox.watch(account, _postId).first, isEmpty);
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'quota defers new entries too, and repeated wakes share one sender',
    () async {
      final restarted = Completer<FeedCommentCreation>();
      repository.send = (request) async {
        if (repository.requests.length == 1) {
          throw const PostgrestException(code: '42901', message: 'quota');
        }
        if (!restarted.isCompleted) return restarted.future;
        return repository.confirm(request);
      };
      await queue('first');
      reachNetwork();
      await _until(
        () async =>
            (await db.select(db.feedCommentOperations).getSingle())
                .rateLimitedUntil !=
            null,
      );
      await queue('second');
      outbox.setForeground(false);
      now = now.add(const Duration(seconds: 20));
      outbox.setForeground(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repository.requests, hasLength(1));
      now = now.add(const Duration(minutes: 1));
      network.value = false;
      network.value = true;
      await _until(() async => repository.requests.length == 2);
      for (var index = 0; index < 5; index++) {
        outbox.setForeground(false);
        outbox.setForeground(true);
      }
      expect(repository.requests, hasLength(2));
      restarted.complete(repository.confirm(repository.requests.last));
      await outbox
          .watch(account, _postId)
          .firstWhere(
            (rows) =>
                rows.length == 2 && rows.every((row) => row.receipt != null),
          );
      expect(repository.requests, hasLength(3));
    },
  );

  test(
    'switching accounts mid-flight scopes reads, writes and receipts',
    () async {
      final response = Completer<FeedCommentCreation>();
      repository.send = (request) => request.owner == 'viewer'
          ? response.future
          : Future.value(repository.confirm(request));
      final received = <String>[];
      final listener = outbox.deliveries.listen(
        (delivery) => received.add(delivery.account.userId),
      );
      addTearDown(listener.cancel);
      await queue('personal draft');
      reachNetwork();
      await _until(() async => repository.requests.isNotEmpty);
      accounts.setAuthenticatedUser('second-account');
      final first = account;
      account = accounts.capture();
      reachNetwork();
      expect(await outbox.watch(account, _postId).first, isEmpty);
      expect(await outbox.watch(first, _postId).first, isEmpty);
      await accounts.drainCommits();
      await outbox.clearUser(first.userId);
      await queue('different account');
      response.complete(repository.confirm(repository.requests.single));
      expect(
        (await entryWhere((row) => row.receipt != null)).text,
        'different account',
      );
      await _until(() async => received.isNotEmpty);
      expect(received, ['second-account']);
      expect(repository.requests.map((request) => request.owner), [
        'viewer',
        'second-account',
      ]);
      expect(
        (await db.select(db.feedCommentOperations).getSingle()).ownerUserId,
        'second-account',
      );
    },
  );

  test(
    'offline comments remain out of server pages and keep stable row ids',
    () async {
      await snapshots.writeCommentPage(account, _popular, (
        page: (comments: const [_parent], next: null),
        expiresAt: now.add(const Duration(minutes: 5)),
      ), allowed: () => true);
      final scope = FeedAccountScope(
        accounts,
        repository,
        postSnapshots: snapshots,
        outbox: outbox,
      );
      final actions = scope.actionsFor(account)!;
      final comments = FeedCommentsCubit(
        repository,
        actions,
        post,
        autoLoad: false,
        networkAvailable: () => network.value,
      );
      addTearDown(() async {
        await comments.close();
        scope.dispose();
      });
      comments.updatePost(
        post,
        confirmed: false,
        offlineUntil: now.add(const Duration(minutes: 5)),
      );
      await _until(() async => comments.state.rows.isNotEmpty);
      final attempts = await Future.wait([
        comments.submit('one tap', replyTo: _parent),
        comments.submit('duplicate tap', replyTo: _parent),
      ]);
      expect(attempts, [true, false]);
      await _until(() async => comments.replies(_parent).isNotEmpty);
      final local = comments.replies(_parent).single;
      expect(local.text, 'one tap');
      expect(comments.available(local), isFalse);
      expect(repository.reads, 0);
      expect(actions.commentCountFor(post), 0);
      expect(
        (await snapshots.readComments(
          account,
          _postId,
        ))[_popular]!.page.comments.map((row) => row.id),
        [_parent.id],
      );
      reachNetwork();
      await _until(
        () async => comments.available(comments.replies(_parent).single),
      );
      expect(comments.replies(_parent).single.id, local.id);
      expect(actions.commentCountFor(post), 1);
      expect(repository.reads, 0);
      comments.updatePost(post, confirmed: true);
      await comments.refresh(interactive: true, visibleThreads: {_parent.id});
      expect(comments.replies(_parent).map((item) => item.id), [local.id]);
    },
  );

  test(
    'a confirmed root goes from local placement to server order on refresh',
    () async {
      await snapshots.writeCommentPage(account, _popular, (
        page: (comments: const [_parent], next: null),
        expiresAt: now.add(const Duration(minutes: 5)),
      ), allowed: () => true);
      final actions = FeedActionsCubit(
        repository,
        account,
        () => accounts.isCurrent(account),
        outbox: outbox,
        postSnapshots: snapshots,
      );
      final comments = FeedCommentsCubit(
        repository,
        actions,
        post,
        autoLoad: false,
      );
      addTearDown(() async {
        await comments.close();
        await actions.close();
      });
      comments.updatePost(post, confirmed: true);
      await _until(() async => comments.state.loaded);
      expect(await comments.submit('new root'), isTrue);
      await _until(() async => comments.state.rows.length == 2);
      final local = comments.state.rows.first;
      expect(comments.pendingEntry(local), isNotNull);
      reachNetwork();
      await _until(
        () async => comments.pendingEntry(comments.state.rows.first) == null,
      );
      expect(comments.state.rows.map((row) => row.id), [local.id, _parent.id]);
      await comments.refresh(interactive: true);
      expect(comments.state.rows.map((row) => row.id), [_parent.id, local.id]);
    },
  );

  test(
    'a failed SQLite insert keeps the composer draft eligible to resubmit',
    () async {
      final actions = FeedActionsCubit(
        repository,
        account,
        () => accounts.isCurrent(account),
        outbox: outbox,
      );
      final comments = FeedCommentsCubit(
        repository,
        actions,
        post,
        autoLoad: false,
      );
      addTearDown(() async {
        await comments.close();
        await actions.close();
      });
      comments.updatePost(post, confirmed: true);
      await db.customStatement('''
      CREATE TRIGGER reject_enqueue BEFORE INSERT ON feed_comment_operations
      BEGIN SELECT RAISE(ABORT, 'test insert failure'); END
    ''');
      await expectLater(comments.submit('unsaved'), throwsA(isA<Exception>()));
      expect(await outbox.watch(account, _postId).first, isEmpty);
      await db.customStatement('DROP TRIGGER reject_enqueue');
      expect(await comments.submit('unsaved'), isTrue);
      expect((await entryWhere((_) => true)).text, 'unsaved');
    },
  );
}

Future<void> _until(Future<bool> Function() condition) async {
  final timer = Stopwatch()..start();
  while (!await condition()) {
    if (timer.elapsed > const Duration(seconds: 3)) fail('state not reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

typedef _Request = ({String id, String owner, String text, String? replyTo});

class _Publication extends MockFeedRepository
    implements IFeedPostRepository, IFeedPublicationRepository {
  final requests = <_Request>[];
  final saved = <String, FeedCommentCreation>{};
  Future<FeedCommentCreation> Function(_Request)? send;
  int reads = 0;

  FeedCommentCreation confirm(_Request request) => saved.putIfAbsent(
    request.id,
    () => (
      comment: FeedComment(
        id: request.id,
        rootId: request.replyTo,
        authorId: request.owner,
        text: request.text,
      ),
      postCount: (count: saved.length + 1, revision: saved.length + 1),
    ),
  );

  @override
  Future<FeedCommentCreation> createComment(
    String postId,
    String id,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  }) async {
    final request = (
      id: id,
      owner: account.userId,
      text: text,
      replyTo: replyTo,
    );
    requests.add(request);
    return send == null ? confirm(request) : send!(request);
  }

  @override
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentSort sort = FeedCommentSort.popular,
    FeedCommentsCursor? cursor,
    String? rootId,
  }) async {
    reads++;
    return (
      comments: rootId == null
          ? [
              _parent,
              for (final receipt in saved.values)
                if (receipt.comment.id == receipt.comment.threadId)
                  receipt.comment,
            ]
          : saved.values
                .map((receipt) => receipt.comment)
                .where((comment) => comment.threadId == rootId)
                .toList(),
      next: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
