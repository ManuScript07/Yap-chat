import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/blocks/blocks.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

void main() {
  late Directory directory;
  late File file;
  late AppDatabase database;
  late AccountSessionController accounts;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yap-feed-snapshot-');
    file = File('${directory.path}${Platform.pathSeparator}cache.sqlite');
    database = AppDatabase.forTesting(NativeDatabase(file));
    accounts = AccountSessionController(initialUserId: 'owner');
  });

  tearDown(() async {
    await database.close();
    if (await file.exists()) await file.delete();
    await directory.delete();
  });

  test('a cold offline detail restores a confirmed quote from Drift', () async {
    const id = 'quote';
    final original = _post('original', friendsOnly: true);
    final quote = _post(id, original: original);
    final store = FeedPostSnapshotStore(database, accounts);
    final live = _PostRepository(() async => quote);
    final firstActions = _actions(accounts, live, store);
    final first = FeedPostDetailsCubit(id, firstActions, null);
    await first.load();
    expect(first.state.confirmed, isTrue);
    await accounts.drainCommits();
    final written = (await store.read(accounts.capture(), id))!;
    await first.close();
    await firstActions.close();
    await database.close();

    database = AppDatabase.forTesting(NativeDatabase(file));
    final reopened = FeedPostSnapshotStore(database, accounts);
    final offline = _PostRepository(
      () async => throw const SocketException('offline'),
    );
    final actions = _actions(accounts, offline, reopened);
    final details = FeedPostDetailsCubit(id, actions, null);
    addTearDown(actions.close);
    addTearDown(details.close);
    await details.load();
    expect(offline.reads, 1);
    expect(details.state.failed, isTrue);
    expect(details.state.confirmed, isFalse);
    final post = details.state.post!;
    expect(post.commentCountRevision, 7);
    expect(post.original?.friendsOnly, isTrue);
    expect(post.original?.text, original.text);
    expect(post.photos.single.thumbnailPath, 'thumb');
    expect(post.formatting, quote.formatting);
    expect(post.coordinates, isNull);
    expect(post.original?.coordinates, isNull);
    expect(post.delivery, isNull);
    expect(post.original?.delivery, isNull);
    expect(
      (await reopened.read(accounts.capture(), id))?.expiresAt,
      written.expiresAt,
    );
    final saved = await database
        .select(database.cachedFeedPostSnapshots)
        .getSingle();
    expect(saved.payload, isNot(contains('latitude')));
    expect(saved.payload, isNot(contains('delivery')));
  });

  test(
    'access denial evicts the post and any saved quote referencing it',
    () async {
      final store = FeedPostSnapshotStore(database, accounts);
      final account = accounts.capture();
      final post = _post('original', friendsOnly: true);
      for (final entry in [
        post,
        _post('quote', original: post),
        _post('unrelated'),
      ]) {
        await store.write(account, _snapshot(entry), allowed: () => true);
      }
      final response = Completer<FeedPost?>();
      final repository = _PostRepository(() => response.future);
      final actions = _actions(accounts, repository, store);
      final details = FeedPostDetailsCubit(post.id, actions, null);
      addTearDown(actions.close);
      addTearDown(details.close);
      final restored = details.stream.firstWhere((state) => state.post != null);
      final request = details.load();
      expect((await restored).post?.id, post.id);
      response.completeError(
        const PostgrestException(message: 'missing', code: 'PT404'),
      );
      await request;
      await accounts.drainCommits();
      expect(details.state.post, isNull);
      expect(await store.read(account, post.id), isNull);
      expect(await store.read(account, 'quote'), isNull);
      expect(await store.read(account, 'unrelated'), isNotNull);
    },
  );

  test(
    'checks the local blocklist for nested authors before showing disk data',
    () async {
      final blocklist = BlocklistCacheDataSource(database: database);
      final store = FeedPostSnapshotStore(
        database,
        accounts,
        blocklist: blocklist,
      );
      final account = accounts.capture();
      final original = _post('other', author: 'blocked');
      final quote = _post('quote', original: original);
      await store.write(account, _snapshot(quote), allowed: () => true);
      await blocklist.replaceAll(account.userId, [
        BlockedUser(
          id: 'blocked',
          username: 'peer',
          displayName: 'peer',
          blockedAt: DateTime.now(),
        ),
      ]);
      expect(await store.read(account, quote.id), isNull);
    },
  );

  test(
    'isolates accounts and expires snapshots at their original deadline',
    () async {
      var now = DateTime.utc(2026, 11, 19, 5, 0, 0, 0, 1);
      final store = FeedPostSnapshotStore(database, accounts, now: () => now);
      final owner = accounts.capture();
      final post = _post('post');
      final expiresAt = now.add(const Duration(minutes: 5));
      final snapshot = (post: post, expiresAt: expiresAt);
      await store.write(owner, snapshot, allowed: () => true);
      accounts.setAuthenticatedUser('another');
      expect(await store.read(accounts.capture(), post.id), isNull);
      expect(await store.read(owner, post.id), isNull);
      await expectLater(
        store.write(owner, snapshot, allowed: () => true),
        throwsA(isA<StaleAccountSessionException>()),
      );
      accounts.setAuthenticatedUser('owner');
      final reopened = accounts.capture();
      now = expiresAt.subtract(const Duration(microseconds: 1));
      expect((await store.read(reopened, post.id))?.expiresAt, expiresAt);
      now = expiresAt;
      expect(await store.read(reopened, post.id), isNull);
      await store.clearUser(owner.userId);
      expect(
        await database.select(database.cachedFeedPostSnapshots).get(),
        isEmpty,
      );
    },
  );

  test('keeps only the newest confirmed snapshots for the account', () async {
    final now = DateTime.utc(2026, 11, 19, 5);
    final store = FeedPostSnapshotStore(database, accounts, now: () => now);
    final account = accounts.capture();
    for (var index = 0; index <= FeedPostSnapshotStore.maximumPosts; index++) {
      await store.write(account, (
        post: _post('post-$index'),
        expiresAt: now.add(Duration(minutes: 5, microseconds: index)),
      ), allowed: () => true);
    }
    expect(await store.read(account, 'post-0'), isNull);
    expect(
      await store.read(account, 'post-${FeedPostSnapshotStore.maximumPosts}'),
      isNotNull,
    );
    expect(
      await database.select(database.cachedFeedPostSnapshots).get(),
      hasLength(FeedPostSnapshotStore.maximumPosts),
    );
  });

  test(
    'network recovery rechecks a restored post once after an in-flight failure',
    () async {
      final store = FeedPostSnapshotStore(database, accounts);
      final post = _post('post');
      await store.write(
        accounts.capture(),
        _snapshot(post),
        allowed: () => true,
      );
      final first = Completer<FeedPost?>();
      final network = ValueNotifier<bool?>(false);
      var checks = 0;
      final repository = _PostRepository(() async {
        checks++;
        if (checks == 1) return first.future;
        return null;
      });
      final actions = _actions(accounts, repository, store);
      final details = FeedPostDetailsCubit(
        post.id,
        actions,
        null,
        networkAvailability: network,
      );
      addTearDown(network.dispose);
      addTearDown(actions.close);
      addTearDown(details.close);
      final restored = details.stream.firstWhere((state) => state.post != null);
      final request = details.load();
      expect((await restored).post?.id, post.id);
      final denied = details.stream.firstWhere(
        (state) => !state.failed && !state.loading && state.post == null,
      );
      network.value = true;
      network.value = false;
      network.value = true;
      first.completeError(const SocketException('offline'));
      await request;
      await denied;
      await accounts.drainCommits();
      expect(repository.reads, 2);
      expect(await store.read(accounts.capture(), post.id), isNull);
    },
  );

  test(
    'migrates an existing v30 database without clearing existing tables',
    () async {
      await database.customStatement('DROP TABLE cached_feed_post_snapshots');
      await database.customStatement(
        'DROP TABLE cached_feed_comment_snapshots',
      );
      await database.customStatement(
        "INSERT INTO cached_app_languages VALUES ('owner', 'ru', 0)",
      );
      await database.customStatement('PRAGMA user_version = 30');
      await database.close();
      database = AppDatabase.forTesting(NativeDatabase(file));
      final store = FeedPostSnapshotStore(database, accounts);
      final account = accounts.capture();
      final post = _post('post');
      await store.write(account, _snapshot(post), allowed: () => true);
      expect(await store.read(account, post.id), isNotNull);
      final language = await database
          .select(database.cachedAppLanguages)
          .getSingle();
      expect(language.languageCode, 'ru');
    },
  );
}

FeedPost _post(
  String id, {
  FeedPost? original,
  bool friendsOnly = false,
  String author = 'author',
}) => FeedPost(
  id: id,
  authorId: author,
  authorName: author,
  text: 'text for $id',
  createdAt: DateTime.utc(2026),
  original: original,
  isQuote: original != null,
  friendsOnly: friendsOnly,
  nearby: true,
  coordinates: (latitude: 54, longitude: 37),
  delivery: (id: 'receipt', expiresAt: DateTime.utc(2027)),
  commentCount: 6,
  commentCountRevision: 7,
  photos: const [
    FeedPhoto(id: 'photo', thumbnailPath: 'thumb', width: 1920, height: 1080),
  ],
  formatting: const [(start: 0, end: 4, style: FeedTextStyle.bold)],
);

FeedPostSnapshot _snapshot(FeedPost post) =>
    (post: post, expiresAt: DateTime.now().add(const Duration(minutes: 5)));

FeedActionsCubit _actions(
  AccountSessionController accounts,
  _PostRepository repository,
  FeedPostSnapshotStore store,
) {
  final account = accounts.capture();
  return FeedActionsCubit(
    repository,
    account,
    () => accounts.isCurrent(account),
    postSnapshots: store,
  );
}

class _PostRepository extends MockFeedRepository
    implements IFeedPostRepository {
  _PostRepository(this.load);
  final Future<FeedPost?> Function() load;
  int reads = 0;

  @override
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account) {
    reads++;
    return load();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
