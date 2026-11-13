import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';

void main() {
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() => f.close());

  test(
    'cached paths are prepared once, scoped and never persisted or downloaded',
    () async {
      final directory = await Directory.systemTemp.createTemp('nearby-paths-');
      addTearDown(() => directory.delete(recursive: true));
      var lookups = 0;
      final local = await _Fixture.create(
        directoryProvider: () async {
          lookups++;
          return directory;
        },
      );
      addTearDown(local.close);
      final person = NearbyPerson(
        id: 'photo-peer',
        username: 'peer',
        displayName: 'Peer',
        activeUntil: DateTime.now().add(const Duration(days: 1)),
        avatarStoragePath: 'peer/avatar.jpg',
      );
      await local.cache.replace(
        'owner',
        const NearbyFilters(),
        people: [person],
        hasMore: true,
      );
      final snapshot = await local.cached();
      final path = snapshot!.people.single.cachedAvatarPath;
      expect(path, isNotNull);
      expect(
        path,
        local.media.localStorageFilePath(
          ownerUserId: 'owner',
          bucket: 'avatars',
          storagePath: 'peer/avatar.jpg',
          mimeType: 'image/jpeg',
        ),
      );
      expect(
        (await local.cache.read(
          'owner',
          const NearbyFilters(),
        ))!.people.single.cachedAvatarPath,
        isNull,
      );
      expect(
        snapshot.people.single.toJson().containsKey('cached_avatar_path'),
        isFalse,
      );
      await local.cached();
      expect(lookups, 1);
      expect(local.remote.calls, isEmpty);
      expect(
        await Directory('${directory.path}/media_cache').exists(),
        isFalse,
      );
      local.account.setAuthenticatedUser('bob');
      await local.cache.replace(
        'bob',
        const NearbyFilters(),
        people: [person],
        hasMore: true,
      );
      expect(
        (await local.cached())!.people.single.cachedAvatarPath,
        isNot(path),
      );
      await local.cache.replace(
        'bob',
        const NearbyFilters(),
        people: [_person('removed')],
        hasMore: false,
      );
      expect((await local.cached())!.people.single.cachedAvatarPath, isNull);
    },
  );
  test('optional directory failure preserves the usable feed', () async {
    final local = await _Fixture.create(
      directoryProvider: () async =>
          throw const FileSystemException('offline cache unavailable'),
    );
    addTearDown(local.close);
    await local.seed(['p1']);
    final snapshot = await local.cached();
    expect(snapshot!.people.single.id, 'p1');
    expect(snapshot.people.single.cachedAvatarPath, isNull);
    expect(local.remote.calls, isEmpty);
  });
  test(
    'account switch while preparing paths rejects the old owner snapshot',
    () async {
      final ready = Completer<Directory>();
      final directory = await Directory.systemTemp.createTemp(
        'nearby-path-scope-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final local = await _Fixture.create(
        directoryProvider: () => ready.future,
      );
      addTearDown(local.close);
      await local.seed(['p1']);
      final reading = local.cached();
      final checked = expectLater(
        reading,
        throwsA(isA<StaleAccountSessionException>()),
      );
      await _tick();
      local.account.setAuthenticatedUser('bob');
      ready.complete(directory);
      await checked;
    },
  );

  test(
    'remote head and next page receive local hints without extra feed requests',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nearby-remote-hints-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final local = await _Fixture.create(
        directoryProvider: () async => directory,
      );
      addTearDown(local.close);
      NearbyPerson person(String id) => NearbyPerson(
        id: id,
        username: id,
        displayName: id,
        activeUntil: DateTime.now().add(const Duration(days: 1)),
        avatarStoragePath: '$id/avatar.jpg',
      );
      final head = local.repo.refreshFeed(const NearbyFilters());
      local.remote.calls.single.done.complete(
        NearbyPageResult(people: [person('first')], hasMore: true),
      );
      final first = await head;
      expect(first.people.single.cachedAvatarPath, isNotNull);
      final loading = local.repo.loadMore(const NearbyFilters());
      await _tick();
      expect(local.remote.calls.length, 2);
      expect(local.remote.calls.last.cursor, 'first');
      local.remote.calls.last.done.complete(
        NearbyPageResult(people: [person('second')], hasMore: false),
      );
      final page = await loading;
      expect(page!.people.map((p) => p.id), ['first', 'second']);
      expect(page.people.every((p) => p.cachedAvatarPath != null), isTrue);
      expect(page.hasMore, isFalse);
      final terminal = await local.repo.loadMore(const NearbyFilters());
      expect(
        terminal!.people.every((person) => person.cachedAvatarPath != null),
        isTrue,
      );
      expect(
        (await local.cache.read(
          'owner',
          const NearbyFilters(),
        ))!.people.every((p) => p.cachedAvatarPath == null),
        isTrue,
      );
      expect(local.remote.calls.length, 2);
    },
  );
  test(
    'a stuck optional directory lookup cannot stall cached feed indefinitely',
    () async {
      final waiting = Completer<Directory>();
      final local = await _Fixture.create(
        directoryProvider: () => waiting.future,
      );
      addTearDown(local.close);
      await local.seed(['p1']);
      final snapshot = await local.cached().timeout(const Duration(seconds: 2));
      expect(snapshot!.people.single.id, 'p1');
      expect(snapshot.people.single.cachedAvatarPath, isNull);
    },
  );

  for (final oldFirst in [false, true]) {
    test('refresh supersedes pending page oldFirst=$oldFirst', () async {
      await f.seed(['old-head', 'old-cursor']);
      final load = f.repo.loadMore(const NearbyFilters());
      final rejected = expectLater(
        load,
        throwsA(isA<NearbyFeedSupersededException>()),
      );
      await _tick();
      expect(f.remote.calls.single.cursor, 'old-cursor');
      final refresh = f.repo.refreshFeed(const NearbyFilters());
      if (oldFirst) {
        f.remote.calls[0].finish(['old-page']);
        await rejected;
      }
      f.remote.calls[1].finish(['fresh-head']);
      await refresh;
      if (!oldFirst) {
        f.remote.calls[0].finish(['old-page']);
        await rejected;
      }
      expect((await f.cached())!.people.map((p) => p.id), ['fresh-head']);
    });
  }

  test('invalidated refresh cannot update cache after its deadline', () async {
    await f.seed(['kept']);
    final refresh = f.repo.refreshFeed(const NearbyFilters());
    final rejected = expectLater(
      refresh,
      throwsA(isA<NearbyFeedSupersededException>()),
    );
    f.repo.invalidateFeed(const NearbyFilters());
    f.remote.calls.single.finish(['late']);
    await rejected;
    expect((await f.cached())!.people.single.id, 'kept');
  });

  test('duplicate refresh and pagination share one in-flight head', () async {
    final a = f.repo.refreshFeed(const NearbyFilters());
    final b = f.repo.refreshFeed(const NearbyFilters());
    final page = f.repo.loadMore(const NearbyFilters());
    expect(f.remote.calls.length, 1);
    f.remote.calls.single.finish(['head']);
    final result = await Future.wait([a, b, page]);
    expect(result.every((s) => s!.people.single.id == 'head'), true);
  });

  test(
    'completion of an old page cannot clear a newer page deduplication',
    () async {
      await f.seed(['old']);
      final old = f.repo.loadMore(const NearbyFilters());
      final rejected = expectLater(
        old,
        throwsA(isA<NearbyFeedSupersededException>()),
      );
      await _tick();
      final refresh = f.repo.refreshFeed(const NearbyFilters());
      f.remote.calls[1].finish(['head']);
      await refresh;
      final page = f.repo.loadMore(const NearbyFilters());
      await _tick();
      f.remote.calls[0].finish(['old-next']);
      await rejected;
      final shared = f.repo.loadMore(const NearbyFilters());
      expect(f.remote.calls.length, 3);
      f.remote.calls[2].finish(['next'], hasMore: false);
      await Future.wait([page, shared]);
      expect((await f.cached())!.people.map((p) => p.id), ['head', 'next']);
    },
  );

  test('generation is checked inside the serialized account commit', () async {
    await f.seed(['kept']);
    final gate = Completer<void>();
    final started = Completer<void>();
    final blocker = f.account.commit(f.account.capture(), () async {
      started.complete();
      await gate.future;
    });
    await started.future;
    final refresh = f.repo.refreshFeed(const NearbyFilters());
    final rejected = expectLater(
      refresh,
      throwsA(isA<NearbyFeedSupersededException>()),
    );
    f.remote.calls.single.finish(['late']);
    await _tick();
    f.repo.invalidateFeed(const NearbyFilters());
    gate.complete();
    await blocker;
    await rejected;
    expect((await f.cached())!.people.single.id, 'kept');
  });

  test(
    'switching account rejects old response without touching either cache',
    () async {
      await f.seed(['owner-old']);
      final refresh = f.repo.refreshFeed(const NearbyFilters());
      final rejected = expectLater(
        refresh,
        throwsA(isA<StaleAccountSessionException>()),
      );
      f.account.setAuthenticatedUser('other');
      f.remote.calls.single.finish(['wrong-owner']);
      await rejected;
      expect(await f.cached(), isNull);
      expect(
        (await f.cache.read('owner', const NearbyFilters()))!.people.single.id,
        'owner-old',
      );
    },
  );

  test('a pending feed cannot restore newly blocked people', () async {
    await f.seed(['blocked', 'kept']);
    final refresh = f.repo.refreshFeed(const NearbyFilters());
    final rejected = expectLater(
      refresh,
      throwsA(isA<NearbyFeedSupersededException>()),
    );
    await f.repo.removeCachedPeople({'blocked'});
    f.remote.calls.single.finish(['blocked', 'kept']);
    await rejected;
    expect((await f.cached())!.people.map((p) => p.id), ['kept']);
  });

  test(
    'repeated non-advancing page stops instead of querying the same cursor',
    () async {
      await f.seed(['head', 'cursor']);
      final page = f.repo.loadMore(const NearbyFilters());
      await _tick();
      f.remote.calls.single.finish(['head', 'cursor']);
      expect((await page)!.hasMore, false);
      await f.repo.loadMore(const NearbyFilters());
      expect(f.remote.calls.length, 1);
    },
  );

  test(
    'cache cap is terminal even when an old snapshot has hasMore=true',
    () async {
      await f.seed([for (var i = 0; i < 150; i++) 'p$i']);
      expect((await f.cached())!.hasMore, false);
      await f.repo.loadMore(const NearbyFilters());
      expect(f.remote.calls, isEmpty);
    },
  );

  test(
    'superseded filter can be queried again without sharing its old future',
    () async {
      const b = NearbyFilters(minimumAge: 30);
      final old = f.repo.refreshFeed(const NearbyFilters());
      final rejected = expectLater(
        old,
        throwsA(isA<NearbyFeedSupersededException>()),
      );
      f.repo.invalidateFeed(const NearbyFilters());
      final other = f.repo.refreshFeed(b);
      final latest = f.repo.refreshFeed(const NearbyFilters());
      expect(f.remote.calls.length, 3);
      f.remote.calls[0].finish(['stale-a']);
      f.remote.calls[1].finish(['b']);
      f.remote.calls[2].finish(['latest-a']);
      await rejected;
      await Future.wait([other, latest]);
      expect((await f.cached())!.people.single.id, 'latest-a');
    },
  );
  test(
    'bounded generation eviction never shares a superseded request',
    () async {
      final pending = <Future<void>>[];
      for (var i = 0; i < 9; i++) {
        final request = f.repo.refreshFeed(NearbyFilters(minimumAge: 18 + i));
        if (i == 0) {
          pending.add(
            expectLater(request, throwsA(isA<NearbyFeedSupersededException>())),
          );
        } else {
          pending.add(request.then<void>((_) {}));
        }
      }
      // Explicitly supersede all other requests so they do not retain a quota or
      // generation lease while testing a return to the evicted filter.
      for (var i = 1; i < 9; i++) {
        f.remote.calls[i].finish(['p$i']);
      }
      await Future.wait(pending.skip(1));
      final latest = f.repo.refreshFeed(const NearbyFilters());
      expect(f.remote.calls.length, 10);
      f.remote.calls[0].finish(['stale']);
      f.remote.calls[9].finish(['latest']);
      await pending.first;
      await latest;
      expect((await f.cached())!.people.single.id, 'latest');
    },
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
NearbyPerson _person(String id) => NearbyPerson(
  id: id,
  username: id,
  displayName: id,
  activeUntil: DateTime.now().toUtc().add(const Duration(days: 1)),
);

class _Call {
  _Call(this.cursor);
  final String? cursor;
  final done = Completer<NearbyPageResult>();
  void finish(List<String> ids, {bool hasMore = true}) => done.complete(
    NearbyPageResult(people: ids.map(_person).toList(), hasMore: hasMore),
  );
}

class _Remote extends NearbyRemoteDataSource {
  _Remote(SupabaseClient client) : super(client: client);
  final calls = <_Call>[];
  @override
  Future<NearbyPageResult> fetch({
    required NearbyFilters filters,
    String? afterUserId,
  }) {
    final call = _Call(afterUserId);
    calls.add(call);
    return call.done.future;
  }
}

class _Fixture {
  _Fixture(
    this.database,
    this.client,
    this.account,
    this.cache,
    this.remote,
    this.media,
    this.repo,
  );
  final AppDatabase database;
  final SupabaseClient client;
  final AccountSessionController account;
  final NearbyCacheDataSource cache;
  final _Remote remote;
  final MediaCacheService media;
  final NearbyRepository repo;
  Future<void> seed(List<String> ids) => cache.replace(
    'owner',
    const NearbyFilters(),
    people: ids.map(_person).toList(),
    hasMore: true,
  );
  Future<NearbyCacheSnapshot?> cached() =>
      repo.getCachedFeed(const NearbyFilters());
  static Future<_Fixture> create({
    Future<Directory> Function()? directoryProvider,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'http://localhost',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final account = AccountSessionController(initialUserId: 'owner');
    final cache = NearbyCacheDataSource(
      preferences: preferences,
      environment: 'test',
    );
    final remote = _Remote(client);
    final media = MediaCacheService(
      database: db,
      cacheDirectoryProvider: directoryProvider,
    );
    final config = AppConfig(
      environment: AppEnvironment.local,
      preferences: preferences,
      talker: Talker(),
      env: const {},
      database: db,
      accountSessionController: account,
    );
    return _Fixture(
      db,
      client,
      account,
      cache,
      remote,
      media,
      NearbyRepository(
        cache: cache,
        remote: remote,
        mediaCache: media,
        accountSessionController: account,
        config: config,
      ),
    );
  }

  Future<void> close() async {
    media.dispose();
    await client.dispose();
    await database.close();
  }
}
