import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final reverseKeys in [false, true]) {
    test(
      'equal timestamps retain the written snapshot reverse=$reverseKeys',
      () async {
        final preferences = _SnapshotPreferences(reverseKeys: reverseKeys);
        final cache = _cache(preferences);
        for (var age = 18; age < 28; age++) {
          final filters = NearbyFilters(minimumAge: age);
          await cache.replace(
            'owner',
            filters,
            people: [_person(age)],
            hasMore: true,
          );
          final latest = await cache.read('owner', filters);
          expect(latest, isNotNull, reason: 'Just written filter age=$age');
          expect(latest!.people.single.id, 'person-$age');
          expect(latest.hasMore, isTrue);
          expect(preferences.getKeys().length, lessThanOrEqualTo(2));
        }
        // The written key wins. Other equal-time keys have a stable tie-breaker,
        // independent of platform key enumeration order.
        expect(
          (await cache.read('owner', const NearbyFilters()))!.people.single.id,
          'person-18',
        );
      },
    );
  }

  test('moving the clock backwards cannot evict the new snapshot', () async {
    final preferences = _SnapshotPreferences();
    final cache = _cache(preferences);
    await cache.replace(
      'owner',
      const NearbyFilters(),
      people: [_person(1)],
      hasMore: true,
    );
    preferences.writeTime = preferences.writeTime.add(const Duration(hours: 1));
    await cache.replace(
      'owner',
      const NearbyFilters(minimumAge: 20),
      people: [_person(2)],
      hasMore: true,
    );
    preferences.writeTime = preferences.writeTime.subtract(
      const Duration(days: 1),
    );
    await cache.replace(
      'owner',
      const NearbyFilters(minimumAge: 22),
      people: [_person(3)],
      hasMore: true,
    );
    expect(
      (await cache.read(
        'owner',
        const NearbyFilters(minimumAge: 22),
      ))!.people.single.id,
      'person-3',
    );
    expect(
      (await cache.read(
        'owner',
        const NearbyFilters(minimumAge: 20),
      ))!.people.single.id,
      'person-2',
    );
    expect(await cache.read('owner', const NearbyFilters()), isNull);
    expect(preferences.getKeys(), hasLength(2));
  });

  test(
    'unequal timestamps preserve the other most recently saved snapshot',
    () async {
      final preferences = _SnapshotPreferences();
      final cache = _cache(preferences);
      for (var age = 18; age <= 22; age += 2) {
        await cache.replace(
          'owner',
          NearbyFilters(minimumAge: age),
          people: [_person(age)],
          hasMore: true,
        );
        preferences.writeTime = preferences.writeTime.add(
          const Duration(seconds: 1),
        );
      }
      expect(await cache.read('owner', const NearbyFilters()), isNull);
      expect(
        (await cache.read(
          'owner',
          const NearbyFilters(minimumAge: 20),
        ))!.people.single.id,
        'person-20',
      );
      expect(
        (await cache.read(
          'owner',
          const NearbyFilters(minimumAge: 22),
        ))!.people.single.id,
        'person-22',
      );
    },
  );

  test(
    'rewriting an existing key protects its new content and metadata',
    () async {
      final preferences = _SnapshotPreferences();
      final cache = _cache(preferences);
      await cache.replace(
        'owner',
        const NearbyFilters(),
        people: [_person(1)],
        hasMore: true,
      );
      await cache.replace(
        'owner',
        const NearbyFilters(minimumAge: 20),
        people: [_person(2)],
        hasMore: true,
      );
      preferences.writeTime = preferences.writeTime.subtract(
        const Duration(days: 1),
      );
      await cache.replace(
        'owner',
        const NearbyFilters(),
        people: [_person(3)],
        hasMore: false,
      );
      final retained = await cache.read('owner', const NearbyFilters());
      expect(retained!.people.single.id, 'person-3');
      expect(retained.hasMore, isFalse);
      expect(retained.cachedAt, preferences.writeTime);
      expect(
        (await cache.read(
          'owner',
          const NearbyFilters(minimumAge: 20),
        ))!.people.single.id,
        'person-2',
      );
    },
  );

  test(
    'append after a third filter retains prior rows, deduplicates and advances',
    () async {
      final preferences = _SnapshotPreferences();
      final cache = _cache(preferences);
      for (var age = 18; age <= 22; age += 2) {
        await cache.replace(
          'owner',
          NearbyFilters(minimumAge: age),
          people: [_person(age)],
          hasMore: true,
        );
      }
      const target = NearbyFilters(minimumAge: 22);
      await cache.append(
        'owner',
        target,
        people: [_person(22), _person(23)],
        hasMore: false,
      );
      final result = await cache.read('owner', target);
      expect(result!.people.map((person) => person.id), [
        'person-22',
        'person-23',
      ]);
      expect(result.hasMore, isFalse);
      expect(preferences.getKeys(), hasLength(2));
    },
  );

  test(
    'retention never touches another owner, environment or saved filters',
    () async {
      final preferences = _SnapshotPreferences();
      final cache = _cache(preferences);
      final otherEnvironment = _cache(preferences, environment: 'another');
      await cache.replace(
        'other',
        const NearbyFilters(),
        people: [_person(90)],
        hasMore: false,
      );
      await otherEnvironment.replace(
        'owner',
        const NearbyFilters(),
        people: [_person(91)],
        hasMore: false,
      );
      const savedFilters = NearbyFilters(minimumAge: 25);
      await cache.writeFilters('owner', savedFilters);
      for (var age = 18; age < 23; age++) {
        await cache.replace(
          'owner',
          NearbyFilters(minimumAge: age),
          people: [_person(age)],
          hasMore: true,
        );
      }
      expect(await cache.readFilters('owner'), savedFilters);
      expect(
        (await cache.read('other', const NearbyFilters()))!.people.single.id,
        'person-90',
      );
      expect(
        (await otherEnvironment.read(
          'owner',
          const NearbyFilters(),
        ))!.people.single.id,
        'person-91',
      );
      await cache.clearUser('owner');
      expect(
        await cache.read('owner', const NearbyFilters(minimumAge: 22)),
        isNull,
      );
      expect(
        (await cache.read('other', const NearbyFilters()))!.people.single.id,
        'person-90',
      );
      expect(
        (await otherEnvironment.read(
          'owner',
          const NearbyFilters(),
        ))!.people.single.id,
        'person-91',
      );
    },
  );

  test(
    'malformed legacy snapshots do not displace the successful write',
    () async {
      final preferences = _SnapshotPreferences();
      preferences.values['nearby.people.test.owner.feed.broken'] = '{broken';
      preferences.values['nearby.people.test.owner.feed.legacy'] = jsonEncode({
        'cached_at': 'invalid',
      });
      final cache = _cache(preferences);
      await cache.replace(
        'owner',
        const NearbyFilters(),
        people: [_person(1)],
        hasMore: true,
      );
      expect(
        (await cache.read('owner', const NearbyFilters()))!.people.single.id,
        'person-1',
      );
      expect(preferences.getKeys(), hasLength(2));
    },
  );

  test(
    'retained pages survive cache recreation and blocking without resurrection',
    () async {
      final preferences = _SnapshotPreferences();
      final cache = _cache(preferences);
      for (var age = 18; age <= 22; age += 2) {
        await cache.replace(
          'owner',
          NearbyFilters(minimumAge: age),
          people: [_person(age)],
          hasMore: true,
        );
      }
      const target = NearbyFilters(minimumAge: 22);
      await cache.append('owner', target, people: [_person(23)], hasMore: true);
      final restoredPreferences = _SnapshotPreferences()
        ..values.addAll(preferences.values);
      final restored = _cache(restoredPreferences);
      expect(
        (await restored.read(
          'owner',
          target,
        ))!.people.map((person) => person.id),
        ['person-22', 'person-23'],
      );
      await restored.removePeople('owner', {'person-22'});
      await restored.append(
        'owner',
        target,
        people: [_person(24)],
        hasMore: false,
      );
      final people = (await restored.read('owner', target))!.people;
      expect(people.map((person) => person.id), ['person-23', 'person-24']);
      expect(restoredPreferences.getKeys(), hasLength(2));
    },
  );

  test('bounds one nearby snapshot and removes newly blocked people', () async {
    final preferences = await SharedPreferences.getInstance();
    final cache = NearbyCacheDataSource(
      preferences: preferences,
      environment: 'test',
    );
    final people = List.generate(170, (index) => _person(index));

    await cache.replace(
      'owner',
      const NearbyFilters(),
      people: people,
      hasMore: false,
    );
    await cache.removePeople('owner', {'person-0', 'person-149'});

    final snapshot = await cache.read('owner', const NearbyFilters());
    expect(snapshot, isNotNull);
    expect(snapshot!.people, hasLength(148));
    expect(
      snapshot.people.map((person) => person.id),
      isNot(contains('person-0')),
    );
    expect(
      snapshot.people.map((person) => person.id),
      isNot(contains('person-149')),
    );
    expect(snapshot.people.last.id, 'person-148');

    await cache.clearUser('owner');
    expect(await cache.read('owner', const NearbyFilters()), isNull);
  });
}

NearbyCacheDataSource _cache(
  SharedPreferences preferences, {
  String environment = 'test',
}) => NearbyCacheDataSource(preferences: preferences, environment: environment);

/// Models clock collisions at the persistence boundary without changing the
/// production clock or depending on the host OS timer resolution.
class _SnapshotPreferences implements SharedPreferences {
  _SnapshotPreferences({this.reverseKeys = false});
  final bool reverseKeys;
  final values = <String, String>{};
  DateTime writeTime = DateTime.utc(2026, 11, 1);

  @override
  Set<String> getKeys() =>
      (reverseKeys ? values.keys.toList().reversed : values.keys).toSet();

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (key.contains('.feed.')) {
      final snapshot = jsonDecode(value) as Map<String, dynamic>;
      snapshot['cached_at'] = writeTime.toIso8601String();
      value = jsonEncode(snapshot);
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NearbyPerson _person(int index) => NearbyPerson(
  id: 'person-$index',
  username: 'user$index',
  displayName: 'Person $index',
  activeUntil: DateTime.now().toUtc().add(const Duration(days: 1)),
);
