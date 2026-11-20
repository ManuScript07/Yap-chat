import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

const _postId = 'post';
const _root = FeedComment(
  id: 'root',
  authorId: 'author',
  text: 'first',
  replyCount: 2,
);
const _reply = FeedComment(
  id: 'reply',
  rootId: 'root',
  authorId: 'peer',
  text: 'second',
);
const _cursor = (sessionId: 'saved-session', position: 19);
const _popular = (_postId, FeedCommentSort.popular, null);
const _newest = (_postId, FeedCommentSort.newFirst, null);
const _oldest = (_postId, FeedCommentSort.old, null);
const _branch = (_postId, FeedCommentSort.old, 'root');

void main() {
  late Directory folder;
  late File file;
  late AppDatabase database;
  late AccountSessionController accounts;
  late FeedPostSnapshotStore store;
  late FeedPost post;
  late DateTime expires;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('yap-feed-comments-');
    file = File('${folder.path}${Platform.pathSeparator}cache.sqlite');
    database = AppDatabase.forTesting(NativeDatabase(file));
    accounts = AccountSessionController(initialUserId: 'viewer');
    store = FeedPostSnapshotStore(database, accounts);
    post = FeedPost(
      id: _postId,
      authorId: 'author',
      authorName: 'author',
      text: 'post',
      createdAt: DateTime.utc(2026),
    );
    expires = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await store.write(accounts.capture(), (
      post: post,
      expiresAt: expires,
    ), allowed: () => true);
  });

  tearDown(() async {
    await database.close();
    if (await file.exists()) await file.delete();
    await folder.delete();
  });

  Future<void> save(
    FeedCommentCacheKey key,
    List<FeedComment> rows, {
    FeedCommentsCursor? next,
  }) => store.writeCommentPage(accounts.capture(), key, (
    page: (comments: rows, next: next),
    expiresAt: expires,
  ), allowed: () => true);

  FeedCommentsCubit open(_Repository repository, {bool? Function()? network}) {
    final account = accounts.capture();
    final actions = FeedActionsCubit(
      repository,
      account,
      () => accounts.isCurrent(account),
      postSnapshots: store,
    );
    final comments = FeedCommentsCubit(
      repository,
      actions,
      post,
      networkAvailable: network,
    );
    addTearDown(actions.close);
    addTearDown(comments.close);
    return comments;
  }

  test(
    'cold offline restore keeps independent sort order, replies and cursors',
    () async {
      const other = FeedComment(id: 'other', authorId: 'author', text: 'other');
      await save(_popular, [_root, other], next: _cursor);
      await save(_newest, [other, _root]);
      await save(_branch, [_reply], next: _cursor);
      await database.close();
      database = AppDatabase.forTesting(NativeDatabase(file));
      store = FeedPostSnapshotStore(database, accounts);

      final repository = _Repository();
      final comments = open(repository, network: () => false);
      final restored = comments.stream.firstWhere((state) => state.loaded);
      comments.updatePost(post, confirmed: false);
      expect((await restored).rows.map((row) => row.id), ['root', 'other']);
      expect(comments.isExpanded(_root.id), isTrue);
      expect(comments.replies(_root).single.id, _reply.id);
      expect(comments.threadStatus(_root.id).more, isTrue);
      await comments.next();
      expect(comments.state.failed, isTrue);
      expect(comments.state.rows, hasLength(2));
      await comments.nextReplies(_root.id);
      expect(comments.replies(_root).single.text, _reply.text);

      comments.selectSort(FeedCommentSort.newFirst);
      expect(comments.state.rows.map((row) => row.id), ['other', 'root']);
      comments.selectSort(FeedCommentSort.old);
      expect(comments.state.loaded, isFalse);
      expect(comments.state.failed, isTrue);
      expect(repository.reads, isEmpty);
    },
  );

  test(
    'an expired saved cursor keeps rows until a successful head retry',
    () async {
      await save(_popular, [_root], next: _cursor);
      final repository = _Repository();
      repository.read = (cursor) async {
        if (cursor != null) {
          throw const PostgrestException(
            message: 'comment_session_expired',
            code: 'PT410',
          );
        }
        return (comments: const [_root], next: null);
      };
      final comments = open(repository);
      final restored = comments.stream.firstWhere((state) => state.loaded);
      comments.updatePost(post, confirmed: true);
      await restored;
      expect(repository.reads, isEmpty);
      await Future.wait([comments.next(), comments.next()]);
      expect(repository.reads, [_cursor]);
      expect(comments.state.failed, isTrue);
      expect(comments.state.rows.single.id, _root.id);
      await comments.next();
      expect(repository.reads, [_cursor, null]);
      expect(comments.state.failed, isFalse);
      expect(comments.state.hasMore, isFalse);
    },
  );

  test(
    'expired cursors rebuild towards the visible row and resume the same bounded search',
    () async {
      await save(_popular, [_root], next: _cursor);
      final repository = _Repository();
      repository.read = (cursor) async {
        if (cursor == _cursor) {
          throw const PostgrestException(
            message: 'comment_session_expired',
            code: 'PT410',
          );
        }
        final page = cursor == null ? 0 : cursor.position + 1;
        return (
          comments: [
            if (page == 5)
              _root
            else
              FeedComment(
                id: 'new-$page',
                authorId: 'author',
                text: 'new page $page',
              ),
          ],
          next: page == 5 ? null : (sessionId: 'replacement', position: page),
        );
      };
      final comments = open(repository);
      comments.visibleAnchors = () => {null: _root.id};
      final restored = comments.stream.firstWhere((state) => state.loaded);
      comments.updatePost(post, confirmed: true);
      await restored;

      await Future.wait([comments.next(), comments.next()]);
      expect(repository.reads, [
        _cursor,
        null,
        for (var page = 0; page < 4; page++)
          (sessionId: 'replacement', position: page),
      ]);
      expect(comments.state.failed, isTrue);
      expect(comments.state.rows.map((row) => row.id), [_root.id]);

      await comments.next();
      expect(repository.reads.last, (sessionId: 'replacement', position: 4));
      expect(repository.reads, hasLength(7));
      expect(comments.state.rows.map((row) => row.id), [
        for (var page = 0; page < 5; page++) 'new-$page',
        _root.id,
      ]);
      expect(comments.state.failed, isFalse);
      expect(comments.state.hasMore, isFalse);
    },
  );

  test(
    'confirmed mutations preserve other pages and hide reported bodies on disk',
    () async {
      await save(_popular, [_root]);
      await save(_oldest, [_root]);
      await save(_branch, [_reply]);
      final repository = _Repository();
      var online = true;
      final comments = open(repository, network: () => online);
      final restored = comments.stream.firstWhere((state) => state.loaded);
      comments.updatePost(post, confirmed: true);
      await restored;

      await comments.toggleLike(comments.state.rows.single);
      await accounts.drainCommits();
      final afterLike = await store.readComments(accounts.capture(), post.id);
      expect(afterLike[_popular]?.page.comments.single.reaction, (
        version: 1,
        liked: true,
        likes: 1,
      ));
      expect(afterLike[_oldest]?.expiresAt, expires);

      expect(await comments.submit('sent online'), isTrue);
      await comments.report(_root, FeedReportReason.spam);
      await accounts.drainCommits();
      final persisted = await store.readComments(accounts.capture(), post.id);
      final roots = persisted[_popular]!.page.comments;
      expect(roots.first.text, 'sent online');
      expect(roots.last.id, _root.id);
      expect(roots.last.authorId, isNull);
      expect(roots.last.text, isNull);
      expect(persisted[_branch]?.page.comments.single.text, _reply.text);
      await store.write(accounts.capture(), (
        post: post,
        expiresAt: expires,
      ), allowed: () => true);
      final updated = (await store.read(accounts.capture(), post.id))!.post;
      expect(updated.commentCount, 3);
      expect(updated.commentCountRevision, 1);
      final physical = await database
          .select(database.cachedFeedCommentSnapshots)
          .get();
      expect(
        physical.every((row) => !row.payload.contains('"text":"first"')),
        isTrue,
      );
      online = false;
      comments.actions.setBlocked({'peer'});
      comments.invalidateAccess();
      await accounts.drainCommits();
      expect(comments.state.rows.first.text, 'sent online');
      expect(comments.replies(_root).single.available, isFalse);
      final scrubbed = await store.readComments(accounts.capture(), post.id);
      expect(scrubbed[_branch]?.page.comments.single.text, isNull);
      expect(repository.reads, isEmpty);
    },
  );

  test(
    'a removed parent clears its comment pages and other accounts cannot restore them',
    () async {
      final owner = accounts.capture();
      await save(_popular, [_root]);
      accounts.setAuthenticatedUser('other');
      expect(await store.readComments(accounts.capture(), post.id), isEmpty);
      expect(await store.readComments(owner, post.id), isEmpty);
      accounts.setAuthenticatedUser(owner.userId);
      final current = accounts.capture();
      expect(await store.readComments(current, post.id), isNotEmpty);
      await store.remove(current, post.id);
      expect(
        await database.select(database.cachedFeedCommentSnapshots).get(),
        isEmpty,
      );
    },
  );

  test(
    'the v31 upgrade retains the saved publication and adds comment pages',
    () async {
      await database.customStatement(
        'DROP TABLE cached_feed_comment_snapshots',
      );
      await database.customStatement('PRAGMA user_version = 31');
      await database.close();
      database = AppDatabase.forTesting(NativeDatabase(file));
      store = FeedPostSnapshotStore(database, accounts);
      final account = accounts.capture();
      expect((await store.read(account, post.id))?.post.text, post.text);
      await save(_popular, [_root]);
      expect(
        (await store.readComments(
          account,
          post.id,
        ))[_popular]?.page.comments.single.id,
        _root.id,
      );
    },
  );
}

class _Repository extends MockFeedRepository
    implements IFeedPostRepository, IFeedPublicationRepository {
  Future<FeedCommentsPage> Function(FeedCommentsCursor?)? read;
  final reads = <FeedCommentsCursor?>[];

  @override
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentsCursor? cursor,
    FeedCommentSort sort = FeedCommentSort.popular,
    String? rootId,
  }) {
    reads.add(cursor);
    return read!(cursor);
  }

  @override
  Future<FeedCommentCreation> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  }) async => (
    comment: FeedComment(id: requestId, authorId: account.userId, text: text),
    postCount: (count: 3, revision: 1),
  );

  @override
  Future<FeedCommentLike> setCommentLiked(
    FeedComment comment,
    FeedReaction current,
    String requestId,
    AccountSessionSnapshot account,
  ) async => (version: 1, liked: true, changed: true);

  @override
  Future<void> reportComment(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
