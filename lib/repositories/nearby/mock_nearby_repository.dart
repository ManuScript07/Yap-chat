import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/abstract_nearby_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby_cache_data_source.dart';

class MockNearbyRepository implements INearbyRepository {
  NearbyFilters _filters = const NearbyFilters();
  final Map<String, NearbyCacheSnapshot> _snapshots = {};

  @override
  Future<NearbyFilters> getFilters() async => _filters;

  @override
  Future<void> saveFilters(NearbyFilters filters) async {
    _filters = filters.normalized();
  }

  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async =>
      _snapshots[filters.cacheKey];

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) async {
    return _snapshots[filters.cacheKey] ??= NearbyCacheSnapshot(
      people: const [],
      hasMore: false,
      cachedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) =>
      getCachedFeed(filters);

  @override
  Future<void> removeCachedPeople(Set<String> userIds) async {
    if (userIds.isEmpty) return;
    for (final entry in _snapshots.entries.toList()) {
      final snapshot = entry.value;
      _snapshots[entry.key] = NearbyCacheSnapshot(
        people: snapshot.people
            .where((person) => !userIds.contains(person.id))
            .toList(growable: false),
        hasMore: snapshot.hasMore,
        cachedAt: snapshot.cachedAt,
      );
    }
  }

  @override
  Future<String?> resolveAvatar(NearbyPerson person) async => person.avatarUrl;

  @override
  Future<void> clearUserCache(String userId) async => _snapshots.clear();
}
