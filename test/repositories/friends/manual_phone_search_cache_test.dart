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
  test('manual phone searches use an isolated 45 second cache', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _TestClock(DateTime.utc(2026, 8, 30, 12));
    final remote = _PhoneSearchRemote();
    final accountSessionController = AccountSessionController(
      initialUserId: 'owner',
    );
    final contactMatchCache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _CacheKeyService(),
    );
    final repository = FriendsRepository(
      config: AppConfig(
        environment: AppEnvironment.prod,
        preferences: await SharedPreferences.getInstance(),
        talker: Talker(),
        env: const {},
        database: database,
        accountSessionController: accountSessionController,
      ),
      cache: FriendsCacheDataSource(
        database: database,
        userIdProvider: () => 'owner',
      ),
      contactMatchCache: contactMatchCache,
      remote: remote,
      mediaCache: MediaCacheService(database: database),
      accountSessionController: accountSessionController,
      clock: clock.call,
    );

    const phone = '+79990000001';
    expect((await repository.readCachedPhoneSearchMatch(phone)).matches, isEmpty);

    expect((await repository.refreshPhoneMatch(phone)).matches[phone]?.id, 'peer');
    expect(remote.calls, 1);
    expect((await repository.readCachedContactMatches([phone])).matches, isEmpty);

    clock.advance(const Duration(seconds: 44));
    await repository.refreshPhoneMatch(phone);
    expect(remote.calls, 1);

    clock.advance(const Duration(seconds: 1));
    await repository.refreshPhoneMatch(phone);
    expect(remote.calls, 2);

    await contactMatchCache.writeResults(
      checkedPhoneNumbers: const [phone, '+79990000002'],
      matches: const {},
      checkedAt: clock.call(),
    );
    await repository.refreshNewFriendContactMatches([phone], {'peer'});
    final contactSnapshot = await repository.readCachedContactMatches([phone]);
    expect(contactSnapshot.matches[phone]?.id, 'peer');
    expect(
      (await repository.readCachedContactMatches(['+79990000002']))
          .checkedPhoneNumbers,
      contains('+79990000002'),
    );
  });
}

class _TestClock {
  _TestClock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}

class _PhoneSearchRemote extends FriendsRemoteDataSource {
  _PhoneSearchRemote()
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );

  int calls = 0;

  @override
  Future<Map<String, FriendCandidate>> matchContactPhones(
    List<String> phoneNumbers,
  ) async {
    calls++;
    return {
      for (final phone in phoneNumbers)
        phone: const FriendCandidate(
          id: 'peer',
          username: 'peer',
          displayName: 'Peer',
          relationship: FriendRelationship.none,
        ),
    };
  }

  @override
  Future<Map<String, FriendCandidate>> matchNewFriendContactPhones(
    List<String> phoneNumbers,
    List<String> friendIds,
  ) async => {
    for (final phone in phoneNumbers)
      if (friendIds.contains('peer'))
        phone: const FriendCandidate(
          id: 'peer',
          username: 'peer',
          displayName: 'Peer',
          relationship: FriendRelationship.friend,
        ),
  };
}

class _CacheKeyService implements IContactCacheKeyService {
  const _CacheKeyService();

  @override
  Future<String> createKey(String normalizedPhone) async =>
      'opaque:$normalizedPhone';
}
