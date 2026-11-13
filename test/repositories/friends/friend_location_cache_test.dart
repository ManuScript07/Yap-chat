import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  late AppDatabase database;
  late FriendsCacheDataSource cache;
  late _LocationRemoteDataSource remote;
  late FriendsRepository repository;
  late AccountSessionController accountSessionController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    remote = _LocationRemoteDataSource();
    accountSessionController = AccountSessionController(initialUserId: 'owner');
    repository = FriendsRepository(
      config: AppConfig(
        environment: AppEnvironment.prod,
        preferences: await SharedPreferences.getInstance(),
        talker: Talker(),
        env: const {},
        database: database,
        accountSessionController: accountSessionController,
      ),
      cache: cache,
      contactMatchCache: ContactMatchCacheDataSource(
        database: database,
        userIdProvider: () => 'owner',
        keyService: const _LocationTestKeyService(),
      ),
      remote: remote,
      mediaCache: MediaCacheService(database: database),
      accountSessionController: accountSessionController,
    );
  });

  tearDown(() => database.close());

  test('returns a fresh cached location without a network refresh', () async {
    final cached = FriendLocation(
      latitude: 55.75,
      longitude: 37.61,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
    await cache.writeLocation('friend', cached);

    expect(
      await repository.getFriendLocation('friend'),
      FriendLocationLookup.current(cached),
    );
    expect(
      await repository.getFriendLocation('friend'),
      FriendLocationLookup.current(cached),
    );
    expect(remote.calls, 0);
  });

  test('coalesces rapid requests when there is no cached location', () async {
    final first = repository.getFriendLocation('friend');
    final second = repository.getFriendLocation('friend');
    await Future<void>.delayed(Duration.zero);
    expect(remote.calls, 1);

    final location = FriendLocation(
      latitude: 55.75,
      longitude: 37.61,
      updatedAt: DateTime.utc(2026, 8, 25, 10),
    );
    remote.complete(location);

    expect(await first, FriendLocationLookup.current(location));
    expect(await second, FriendLocationLookup.current(location));
    expect(remote.calls, 1);
    expect(await cache.readLocation('friend'), location);
  });

  test('drops a late location response after switching accounts', () async {
    final request = repository.getFriendLocation('friend');
    await Future<void>.delayed(Duration.zero);

    accountSessionController.setAuthenticatedUser(null);
    accountSessionController.setAuthenticatedUser('other-owner');
    remote.complete(
      FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: DateTime.utc(2026, 8, 25, 10),
      ),
    );

    await expectLater(request, throwsA(isA<StaleAccountSessionException>()));
    expect(await cache.readLocation('friend', ownerUserId: 'owner'), isNull);
    expect(
      await cache.readLocation('friend', ownerUserId: 'other-owner'),
      isNull,
    );
  });

  test(
    'keeps a recent cached point available without a location refresh',
    () async {
      final cached = FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().toUtc().millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      await cache.writeLocation('friend', cached);

      expect(
        await repository.getFriendLocation('friend'),
        FriendLocationLookup.current(cached),
      );
      expect(await cache.readLocation('friend'), cached);
      expect(remote.calls, 0);
    },
  );

  test(
    'keeps an old point while the friend still shares exact location',
    () async {
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
        isUtc: true,
      );
      final cached = FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: updatedAt,
      );
      await cache.writeLocation('friend', cached);

      expect(await repository.getCachedFriendLocation('friend'), cached);
    },
  );

  test(
    'expires a frozen point 24 hours after exact sharing is hidden',
    () async {
      final cached = FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      await cache.writeLocation('friend', cached);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        'friend_location_visibility.owner.friend.hidden',
        true,
      );

      expect(await repository.getCachedFriendLocation('friend'), isNull);
      expect(await cache.readLocation('friend'), isNull);
    },
  );

  test('remembers that exact sharing was hidden for a cached point', () async {
    final request = repository.getFriendLocation('friend');
    await Future<void>.delayed(Duration.zero);
    remote.completeLookup(const FriendLocationLookup.hidden());

    expect(await request, const FriendLocationLookup.hidden());
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('friend_location_visibility.owner.friend.hidden'),
      isTrue,
    );
  });
}

class _LocationRemoteDataSource extends FriendsRemoteDataSource {
  _LocationRemoteDataSource()
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );

  final Completer<FriendLocationLookup> _completer = Completer();
  final Completer<void> _completed = Completer();
  int calls = 0;

  Future<void> get completed => _completed.future;

  void complete(FriendLocation? location) => _completer.complete(
    location == null
        ? const FriendLocationLookup.unavailable()
        : FriendLocationLookup.current(location),
  );

  void completeLookup(FriendLocationLookup lookup) =>
      _completer.complete(lookup);

  @override
  Future<FriendLocationLookup> getFriendLocation(String friendId) async {
    calls++;
    final result = await _completer.future;
    if (!_completed.isCompleted) _completed.complete();
    return result;
  }
}

class _LocationTestKeyService implements IContactCacheKeyService {
  const _LocationTestKeyService();

  @override
  Future<String> createKey(String normalizedPhone) async => normalizedPhone;
}
