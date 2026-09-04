import 'dart:async';

import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/abstract_nearby_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby_cache_data_source.dart';
import 'package:yap_chat/repositories/nearby/nearby_remote_data_source.dart';

class NearbyRepository implements INearbyRepository {
  NearbyRepository({
    required NearbyCacheDataSource cache,
    required NearbyRemoteDataSource remote,
    required MediaCacheService mediaCache,
    required AccountSessionController accountSessionController,
    required AppConfig config,
  }) : _cache = cache,
       _remote = remote,
       _mediaCache = mediaCache,
       _accountSessionController = accountSessionController,
       _config = config;

  final NearbyCacheDataSource _cache;
  final NearbyRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final AccountSessionController _accountSessionController;
  final AppConfig _config;
  final Map<String, Future<NearbyCacheSnapshot>> _activeRefreshes = {};
  final Map<String, Future<NearbyCacheSnapshot?>> _activeLoads = {};

  @override
  Future<NearbyFilters> getFilters() async {
    final scope = _accountSessionController.capture();
    final filters = await _cache.readFilters(scope.userId);
    _accountSessionController.ensureCurrent(scope);
    return filters;
  }

  @override
  Future<void> saveFilters(NearbyFilters filters) async {
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.writeFilters(scope.userId, filters),
    );
  }

  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async {
    final scope = _accountSessionController.capture();
    final value = await _cache.read(scope.userId, filters);
    _accountSessionController.ensureCurrent(scope);
    return value;
  }

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) {
    final scope = _accountSessionController.capture();
    final key = _key(scope, filters);
    final active = _activeRefreshes[key];
    if (active != null) return active;
    final future = _remote.fetch(filters: filters).then((page) async {
      final retained = page.people
          .where((person) => person.isStillActive)
          .toList(growable: false);
      await _accountSessionController.commit(
        scope,
        () => _cache.replace(
          scope.userId,
          filters,
          people: retained,
          hasMore: page.hasMore,
        ),
      );
      return NearbyCacheSnapshot(
        people: List.unmodifiable(retained),
        hasMore: page.hasMore,
        cachedAt: DateTime.now().toUtc(),
      );
    });
    _activeRefreshes[key] = future;
    return future.whenComplete(() => _activeRefreshes.remove(key));
  }

  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async {
    final scope = _accountSessionController.capture();
    final key = _key(scope, filters);
    final active = _activeLoads[key];
    if (active != null) return active;
    final future = _loadMore(scope, filters);
    _activeLoads[key] = future;
    return future.whenComplete(() => _activeLoads.remove(key));
  }

  Future<NearbyCacheSnapshot?> _loadMore(
    AccountSessionSnapshot scope,
    NearbyFilters filters,
  ) async {
    final cached = await _cache.read(scope.userId, filters);
    _accountSessionController.ensureCurrent(scope);
    if (cached == null || !cached.hasMore) return cached;
    // The activity window can age every locally saved row out. There is then
    // no safe cursor, so restart from the first server page instead of leaving
    // an empty feed with hasMore permanently set.
    if (cached.people.isEmpty) return await refreshFeed(filters);
    final page = await _remote.fetch(
      filters: filters,
      afterUserId: cached.people.last.id,
    );
    _accountSessionController.ensureCurrent(scope);
    final retained = page.people
        .where((person) => person.isStillActive)
        .toList(growable: false);
    await _accountSessionController.commit(
      scope,
      () => _cache.append(
        scope.userId,
        filters,
        people: retained,
        hasMore: page.hasMore,
      ),
    );
    return _cache.read(scope.userId, filters);
  }

  @override
  Future<void> removeCachedPeople(Set<String> userIds) async {
    if (userIds.isEmpty) return;
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.removePeople(scope.userId, userIds),
    );
  }

  @override
  Future<String?> resolveAvatar(NearbyPerson person) async {
    final scope = _accountSessionController.capture();
    try {
      if (person.avatarStoragePath case final path?) {
        final local = await _mediaCache.cacheStorageFile(
          ownerUserId: scope.userId,
          bucket: 'avatars',
          storagePath: path,
          mimeType: 'image/jpeg',
        );
        _accountSessionController.ensureCurrent(scope);
        return local;
      }
      if (person.avatarUrl case final url? when url.isNotEmpty) {
        final local = await _mediaCache.cacheNetworkFile(
          ownerUserId: scope.userId,
          bucket: MediaCacheService.externalAvatarsBucket,
          url: url,
        );
        _accountSessionController.ensureCurrent(scope);
        return local;
      }
    } on StaleAccountSessionException {
      return null;
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Nearby avatar caching failed');
    }
    return null;
  }

  @override
  Future<void> clearUserCache(String userId) => _cache.clearUser(userId);

  String _key(AccountSessionSnapshot scope, NearbyFilters filters) =>
      '${scope.generation}\u0000${scope.userId}\u0000${filters.normalized().cacheKey}';
}
