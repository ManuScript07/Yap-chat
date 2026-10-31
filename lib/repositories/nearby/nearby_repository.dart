import 'dart:async';

import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'abstract_nearby_repository.dart';
import 'nearby_cache_data_source.dart';
import 'nearby_remote_data_source.dart';

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
  final Map<String, Object> _feedGenerations = {};

  Object _newGeneration(String key) {
    final generation = Object();
    _feedGenerations.remove(key);
    _feedGenerations[key] = generation;
    // Only two filter snapshots persist; pending query bookkeeping is bounded
    // too. Evicting a token also safely supersedes any old associated work.
    while (_feedGenerations.length > 8) {
      final evicted = _feedGenerations.keys.first;
      _feedGenerations.remove(evicted);
      _activeLoads.remove(evicted);
      _activeRefreshes.remove(evicted);
    }
    _activeLoads.remove(key);
    _activeRefreshes.remove(key);
    return generation;
  }

  void _ensureGeneration(String key, Object generation) {
    if (!identical(_feedGenerations[key], generation)) {
      throw const NearbyFeedSupersededException();
    }
  }

  @override
  void invalidateFeed(NearbyFilters filters) {
    if (_accountSessionController.userId == null) return;
    _newGeneration(_key(_accountSessionController.capture(), filters));
  }

  void _invalidateOwner(String userId) {
    for (final key in _feedGenerations.keys.toList()) {
      if (key.split('\u0000')[1] == userId) _newGeneration(key);
    }
  }

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
    return value == null ? null : await _withLocalAvatarPaths(scope, value);
  }

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) {
    final scope = _accountSessionController.capture();
    final key = _key(scope, filters);
    final active = _activeRefreshes[key];
    if (active != null) return active;
    final generation = _newGeneration(key);
    final future = _remote.fetch(filters: filters).then((page) async {
      final retained = page.people
          .where((person) => person.isStillActive)
          .toList(growable: false);
      await _accountSessionController.commit(scope, () {
        _ensureGeneration(key, generation);
        return _cache.replace(
          scope.userId,
          filters,
          people: retained,
          hasMore: page.hasMore,
        );
      });
      _ensureGeneration(key, generation);
      final snapshot = await _withLocalAvatarPaths(
        scope,
        NearbyCacheSnapshot(
          people: List.unmodifiable(retained),
          hasMore: page.hasMore,
          cachedAt: DateTime.now().toUtc(),
        ),
      );
      _ensureGeneration(key, generation);
      return snapshot;
    });
    _activeRefreshes[key] = future;
    return future.whenComplete(() {
      if (identical(_activeRefreshes[key], future)) {
        _activeRefreshes.remove(key);
      }
    });
  }

  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async {
    final scope = _accountSessionController.capture();
    final key = _key(scope, filters);
    final refresh = _activeRefreshes[key];
    if (refresh != null) return refresh;
    final active = _activeLoads[key];
    if (active != null) return active;
    final generation = _feedGenerations[key] ?? _newGeneration(key);
    final future = _loadMore(scope, filters, key, generation);
    _activeLoads[key] = future;
    return future.whenComplete(() {
      if (identical(_activeLoads[key], future)) _activeLoads.remove(key);
    });
  }

  Future<NearbyCacheSnapshot?> _loadMore(
    AccountSessionSnapshot scope,
    NearbyFilters filters,
    String key,
    Object generation,
  ) async {
    final cached = await _cache.read(scope.userId, filters);
    _accountSessionController.ensureCurrent(scope);
    _ensureGeneration(key, generation);
    if (cached == null) return null;
    if (!cached.hasMore) {
      final prepared = await _withLocalAvatarPaths(scope, cached);
      _ensureGeneration(key, generation);
      return prepared;
    }
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
    final existingIds = cached.people.map((person) => person.id).toSet();
    final advances = retained.any((person) => !existingIds.contains(person.id));
    await _accountSessionController.commit(scope, () {
      _ensureGeneration(key, generation);
      return _cache.append(
        scope.userId,
        filters,
        people: retained,
        hasMore: page.hasMore && advances,
      );
    });
    final snapshot = await _cache.read(scope.userId, filters);
    _accountSessionController.ensureCurrent(scope);
    _ensureGeneration(key, generation);
    final prepared = snapshot == null
        ? null
        : await _withLocalAvatarPaths(scope, snapshot);
    _ensureGeneration(key, generation);
    return prepared;
  }

  Future<NearbyCacheSnapshot> _withLocalAvatarPaths(
    AccountSessionSnapshot scope,
    NearbyCacheSnapshot snapshot,
  ) async {
    try {
      await _mediaCache.prepareLocalPaths().timeout(
        const Duration(milliseconds: 250),
      );
    } catch (_) {
      // Optional local hints must not prevent displaying a usable feed.
      _accountSessionController.ensureCurrent(scope);
      return snapshot;
    }
    _accountSessionController.ensureCurrent(scope);
    return NearbyCacheSnapshot(
      people: List.unmodifiable(
        snapshot.people.map((person) {
          final storage = person.avatarStoragePath?.isNotEmpty == true;
          final source = storage ? person.avatarStoragePath : person.avatarUrl;
          return person.withCachedAvatarPath(
            source == null || source.isEmpty
                ? null
                : _mediaCache.localStorageFilePath(
                    ownerUserId: scope.userId,
                    bucket: storage
                        ? 'avatars'
                        : MediaCacheService.externalAvatarsBucket,
                    storagePath: source,
                    mimeType: storage ? 'image/jpeg' : null,
                  ),
          );
        }),
      ),
      hasMore: snapshot.hasMore,
      cachedAt: snapshot.cachedAt,
    );
  }

  @override
  Future<void> removeCachedPeople(Set<String> userIds) async {
    if (userIds.isEmpty) return;
    final scope = _accountSessionController.capture();
    _invalidateOwner(scope.userId);
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
  Future<void> clearUserCache(String userId) {
    _invalidateOwner(userId);
    return _cache.clearUser(userId);
  }

  String _key(AccountSessionSnapshot scope, NearbyFilters filters) =>
      '${scope.generation}\u0000${scope.userId}\u0000${filters.normalized().cacheKey}';
}
