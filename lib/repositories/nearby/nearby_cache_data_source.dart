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
      return NearbyFilters.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
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

  Future<void> replace(
    String ownerUserId,
    NearbyFilters filters, {
    required List<NearbyPerson> people,
    required bool hasMore,
  }) => _write(
    ownerUserId,
    filters,
    people: people,
    hasMore: hasMore,
  );

  Future<void> append(
    String ownerUserId,
    NearbyFilters filters, {
    required List<NearbyPerson> people,
    required bool hasMore,
  }) async {
    final existing = await read(ownerUserId, filters);
    final byId = <String, NearbyPerson>{
      for (final person in existing?.people ?? const <NearbyPerson>[]) person.id: person,
      for (final person in people) person.id: person,
    };
    await _write(
      ownerUserId,
      filters,
      people: byId.values.take(180).toList(growable: false),
      hasMore: hasMore,
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
  }) => _preferences.setString(
    _feedKey(ownerUserId, filters),
    jsonEncode({
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'has_more': hasMore,
      'people': people.map((person) => person.toJson()).toList(growable: false),
    }),
  );

  String _filtersKey(String ownerUserId) => '$_keyPrefix$ownerUserId.filters';

  String _feedKey(String ownerUserId, NearbyFilters filters) =>
      '$_keyPrefix$ownerUserId.feed.${filters.normalized().cacheKey}';
}
