import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/nearby/data/data.dart';

class NearbyCacheSnapshot {
  const NearbyCacheSnapshot({
    required this.people,
    required this.hasMore,
    required this.cachedAt,
  });

  final List<NearbyPerson> people;
  final bool hasMore;
  final DateTime cachedAt;
}

/// A compact account-and-filter-scoped feed snapshot.
///
/// Unlike transient query caches this snapshot is intentionally retained until
/// the user refreshes it. Rows which age out of the three-day activity window
/// are hidden on read but retained on disk, so a temporary offline period
/// never erases a previously loaded feed.
class NearbyCacheDataSource {
  static const _maximumSnapshotsPerUser = 2;
  static const maximumPeoplePerSnapshot = 100;

  NearbyCacheDataSource({
    required SharedPreferences preferences,
    required String environment,
  }) : _preferences = preferences,
       _keyPrefix = 'nearby.people.$environment.';

  final SharedPreferences _preferences;
  final String _keyPrefix;

  Future<NearbyFilters> readFilters(String ownerUserId) async {
    final raw = _preferences.getString(_filtersKey(ownerUserId));
    if (raw == null) return const NearbyFilters();
    try {
      return NearbyFilters.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const NearbyFilters();
    }
  }

  Future<void> writeFilters(String ownerUserId, NearbyFilters filters) async {
    await _preferences.setString(
      _filtersKey(ownerUserId),
      jsonEncode(filters.normalized().toJson()),
    );
  }

  Future<NearbyCacheSnapshot?> read(
    String ownerUserId,
    NearbyFilters filters,
  ) async {
    final raw = _preferences.getString(_feedKey(ownerUserId, filters));
    if (raw == null) return null;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final encodedPeople = value['people'];
      final cachedAt = DateTime.tryParse(value['cached_at'] as String? ?? '');
      if (encodedPeople is! List || cachedAt == null) return null;
      final people = encodedPeople
          .whereType<Map>()
          .map((item) => NearbyPerson.fromJson(Map<String, dynamic>.from(item)))
          .where((person) => person.id.isNotEmpty && person.isStillActive)
          .toList(growable: false);
      return NearbyCacheSnapshot(
        people: List.unmodifiable(people),
        hasMore: value['has_more'] as bool? ?? false,
        cachedAt: cachedAt.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  /// The nearby RPC only succeeds when the server has a location younger than
  /// twelve hours. Keep that confirmation separately from a filter snapshot:
  /// changing filters must not make a still-valid server location disappear
  /// while the device GPS is disabled or the app is offline.
  Future<DateTime?> readLocationConfirmation(String ownerUserId) async =>
      DateTime.tryParse(
        _preferences.getString(_locationConfirmationKey(ownerUserId)) ?? '',
      )?.toUtc();

  Future<void> replace(
    String ownerUserId,
    NearbyFilters filters, {
    required List<NearbyPerson> people,
    required bool hasMore,
  }) => _write(ownerUserId, filters, people: people, hasMore: hasMore);

  Future<void> append(
    String ownerUserId,
    NearbyFilters filters, {
    required List<NearbyPerson> people,
    required bool hasMore,
  }) async {
    final existing = await read(ownerUserId, filters);
    final byId = <String, NearbyPerson>{
      for (final person in existing?.people ?? const <NearbyPerson>[])
        person.id: person,
      for (final person in people) person.id: person,
    };
    await _write(
      ownerUserId,
      filters,
      people: byId.values
          .take(maximumPeoplePerSnapshot)
          .toList(growable: false),
      hasMore: hasMore,
    );
  }

  /// Removes newly blocked people from every locally retained filter snapshot.
  /// This is deliberately local-only: an unblock must not resurrect a stale
  /// cached result that the server may no longer consider nearby.
  Future<void> removePeople(String ownerUserId, Set<String> userIds) async {
    if (userIds.isEmpty) return;
    final prefix = '$_keyPrefix$ownerUserId.feed.';
    final keys = _preferences.getKeys().where((key) => key.startsWith(prefix));
    await Future.wait(
      keys.map((key) async {
        final raw = _preferences.getString(key);
        if (raw == null) return;
        try {
          final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final people = value['people'];
          if (people is! List) return;
          final retained = people
              .where((item) {
                if (item is! Map) return false;
                return !userIds.contains(item['id'] as String?);
              })
              .toList(growable: false);
          if (retained.length == people.length) return;
          value['people'] = retained;
          await _preferences.setString(key, jsonEncode(value));
        } catch (_) {
          // A corrupt optional snapshot is ignored and will be replaced by the
          // next explicit server refresh.
        }
      }),
    );
  }

  Future<void> clearUser(String ownerUserId) async {
    final prefix = '$_keyPrefix$ownerUserId.';
    final keys = _preferences.getKeys().where(
      (key) => key == _filtersKey(ownerUserId) || key.startsWith(prefix),
    );
    await Future.wait(keys.map(_preferences.remove));
  }

  Future<void> _write(
    String ownerUserId,
    NearbyFilters filters, {
    required List<NearbyPerson> people,
    required bool hasMore,
  }) async {
    await _preferences.setString(
      _feedKey(ownerUserId, filters),
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'has_more': hasMore,
        'people': people
            .take(maximumPeoplePerSnapshot)
            .map((person) => person.toJson())
            .toList(growable: false),
      }),
    );
    await _preferences.setString(
      _locationConfirmationKey(ownerUserId),
      DateTime.now().toUtc().toIso8601String(),
    );
    await _trimSnapshots(ownerUserId);
  }

  Future<void> _trimSnapshots(String ownerUserId) async {
    final prefix = '$_keyPrefix$ownerUserId.feed.';
    final snapshots = <({String key, DateTime cachedAt})>[];
    for (final key in _preferences.getKeys().where(
      (key) => key.startsWith(prefix),
    )) {
      final raw = _preferences.getString(key);
      if (raw == null) continue;
      try {
        final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        snapshots.add((
          key: key,
          cachedAt:
              DateTime.tryParse(value['cached_at'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));
      } catch (_) {
        snapshots.add((
          key: key,
          cachedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));
      }
    }
    snapshots.sort((left, right) => right.cachedAt.compareTo(left.cachedAt));
    await Future.wait(
      snapshots
          .skip(_maximumSnapshotsPerUser)
          .map((snapshot) => _preferences.remove(snapshot.key)),
    );
  }

  String _filtersKey(String ownerUserId) => '$_keyPrefix$ownerUserId.filters';

  String _locationConfirmationKey(String ownerUserId) =>
      '$_keyPrefix$ownerUserId.location_confirmation';

  String _feedKey(String ownerUserId, NearbyFilters filters) =>
      '$_keyPrefix$ownerUserId.feed.${filters.normalized().cacheKey}';
}
