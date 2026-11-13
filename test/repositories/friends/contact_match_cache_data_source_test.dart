import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  group('ContactMatchCachePolicy', () {
    const policy = ContactMatchCachePolicy();
    final now = DateTime.utc(2026, 8, 25, 12);

    test('refreshes positive matches after 24 hours', () {
      final candidate = _candidate();
      expect(
        policy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: true,
            checkedAt: now.subtract(const Duration(hours: 23)),
            candidate: candidate,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        policy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: true,
            checkedAt: now.subtract(const Duration(hours: 24)),
            candidate: candidate,
          ),
          now,
        ),
        isTrue,
      );
    });

    test('refreshes negative matches after 2 hours', () {
      expect(
        policy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: false,
            checkedAt: now.subtract(const Duration(minutes: 119)),
          ),
          now,
        ),
        isFalse,
      );
      expect(
        policy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: false,
            checkedAt: now.subtract(const Duration(hours: 2)),
          ),
          now,
        ),
        isTrue,
      );
    });

    test('supports a short, symmetric manual-search policy', () {
      const manualPolicy = ContactMatchCachePolicy(
        positiveTtl: Duration(seconds: 45),
        negativeTtl: Duration(seconds: 45),
      );
      expect(
        manualPolicy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: true,
            checkedAt: now.subtract(const Duration(seconds: 44)),
            candidate: _candidate(),
          ),
          now,
        ),
        isFalse,
      );
      expect(
        manualPolicy.shouldRefresh(
          ContactMatchCacheRecord(
            isRegistered: false,
            checkedAt: now.subtract(const Duration(seconds: 45)),
          ),
          now,
        ),
        isTrue,
      );
    });
  });

  test('stores positive and negative results under opaque phone keys', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _FakeKeyService(),
    );
    final checkedAt = DateTime.utc(2026, 8, 25, 12);

    await cache.writeResults(
      checkedPhoneNumbers: const ['+79990000001', '+79990000002'],
      matches: {'+79990000001': _candidate()},
      checkedAt: checkedAt,
    );

    final records = await cache.read(const [
      '+79990000001',
      '+79990000002',
    ]);
    expect(records, hasLength(2));
    expect(records['+79990000001']?.candidate?.id, 'candidate');
    expect(records['+79990000002']?.isRegistered, isFalse);
    final rows = await database.select(database.cachedContactMatches).get();
    expect(
      rows.map((row) => row.phoneKey),
      containsAll(const ['opaque:+79990000001', 'opaque:+79990000002']),
    );
    expect(
      rows.map((row) => row.phoneKey),
      isNot(contains(anyOf('+79990000001', '+79990000002'))),
    );
  });

  test('removes cache entries for numbers no longer in the address book', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _FakeKeyService(),
    );
    await cache.writeResults(
      checkedPhoneNumbers: const ['+79990000001', '+79990000002'],
      matches: const {},
      checkedAt: DateTime.utc(2026, 8, 25),
    );

    await cache.retainOnly(const ['+79990000002']);

    expect((await cache.read(const ['+79990000001'])), isEmpty);
    expect((await cache.read(const ['+79990000002'])), hasLength(1));
  });

  test('keeps manual phone-search records separate from address-book records',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _FakeKeyService(),
    );
    const phone = '+79990000001';
    final checkedAt = DateTime.utc(2026, 8, 25);

    await cache.writeResults(
      checkedPhoneNumbers: const [phone],
      matches: {phone: _candidate()},
      checkedAt: checkedAt,
    );
    await cache.writeResults(
      checkedPhoneNumbers: const [phone],
      matches: const {},
      checkedAt: checkedAt,
      scope: PhoneMatchCacheScope.manualSearch,
    );

    expect((await cache.read(const [phone]))[phone]?.candidate?.id, 'candidate');
    expect(
      (await cache.read(
        const [phone],
        scope: PhoneMatchCacheScope.manualSearch,
      ))[phone]?.isRegistered,
      isFalse,
    );

    await cache.retainOnly(const []);
    expect(await cache.read(const [phone]), isEmpty);
    expect(
      await cache.read(
        const [phone],
        scope: PhoneMatchCacheScope.manualSearch,
      ),
      hasLength(1),
    );
  });

  test('prunes expired manual phone-search records without touching contacts',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _FakeKeyService(),
    );
    const expiredPhone = '+79990000001';
    const freshPhone = '+79990000002';
    final now = DateTime.utc(2026, 8, 25, 12);
    await cache.writeResults(
      checkedPhoneNumbers: const [expiredPhone, freshPhone],
      matches: const {},
      checkedAt: now.subtract(const Duration(seconds: 46)),
      scope: PhoneMatchCacheScope.manualSearch,
    );
    await cache.writeResults(
      checkedPhoneNumbers: const [freshPhone],
      matches: {freshPhone: _candidate()},
      checkedAt: now.subtract(const Duration(seconds: 44)),
      scope: PhoneMatchCacheScope.manualSearch,
    );
    await cache.writeResults(
      checkedPhoneNumbers: const [expiredPhone],
      matches: {expiredPhone: _candidate()},
      checkedAt: now,
    );

    await cache.pruneExpiredManualSearchMatches(
      expiredBefore: now.subtract(const Duration(seconds: 45)),
    );

    expect(
      await cache.read(
        const [expiredPhone],
        scope: PhoneMatchCacheScope.manualSearch,
      ),
      isEmpty,
    );
    expect(
      await cache.read(
        const [freshPhone],
        scope: PhoneMatchCacheScope.manualSearch,
      ),
      hasLength(1),
    );
    expect((await cache.read(const [expiredPhone]))[expiredPhone]?.candidate?.id,
        'candidate');
  });

  test('handles address books larger than the SQLite variable limit', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _FakeKeyService(),
    );
    final phoneNumbers = List.generate(
      1200,
      (index) => '+7999${index.toString().padLeft(7, '0')}',
    );
    await cache.writeResults(
      checkedPhoneNumbers: phoneNumbers,
      matches: const {},
      checkedAt: DateTime.utc(2026, 8, 25),
    );

    expect(await cache.read(phoneNumbers), hasLength(1200));
    await cache.retainOnly(phoneNumbers.take(1000));
    expect(await cache.read(phoneNumbers), hasLength(1000));
  });
}

FriendCandidate _candidate() => const FriendCandidate(
  id: 'candidate',
  username: 'max',
  displayName: 'Максим',
  friendCount: 4,
  relationship: FriendRelationship.none,
);

class _FakeKeyService implements IContactCacheKeyService {
  const _FakeKeyService();

  @override
  Future<String> createKey(String normalizedPhone) async =>
      'opaque:$normalizedPhone';
}
