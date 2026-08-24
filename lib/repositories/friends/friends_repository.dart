import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_remote_data_source.dart';

class FriendsRepository implements IFriendsRepository {
  FriendsRepository({
    required AppConfig config,
    required FriendsCacheDataSource cache,
    required FriendsRemoteDataSource remote,
    required MediaCacheService mediaCache,
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaCache = mediaCache;

  final AppConfig _config;
  final FriendsCacheDataSource _cache;
  final FriendsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final Uuid _uuid = const Uuid();
  StreamSubscription<void>? _changesSubscription;
  Future<void>? _activeSync;
  final Map<String, ({DateTime cachedAt, List<FriendCandidate> results})>
  _searchCache = {};
  final Map<String, Future<List<FriendCandidate>>> _activeSearches = {};

  @override
  Stream<List<Friend>> watchFriends() {
    unawaited(_ensureStarted());
    return _cache.watchFriends();
  }

  @override
  Stream<List<FriendRequest>> watchRequests() {
    unawaited(_ensureStarted());
    return _cache.watchRequests();
  }

  @override
  Future<List<Friend>> getFriends() async {
    await _synchronize();
    return _cache.readFriends();
  }

  @override
  Future<List<FriendRequest>> getRequests() async {
    await _synchronize();
    return _cache.readRequests();
  }

  @override
  Future<List<FriendCandidate>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    final cached = _searchCache[normalized];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) <
            const Duration(seconds: 45)) {
      return cached.results;
    }
    final active = _activeSearches[normalized];
    if (active != null) return active;
    final future = _remote.searchUsers(normalized).then((results) {
      _searchCache[normalized] = (cachedAt: DateTime.now(), results: results);
      while (_searchCache.length > 20) {
        _searchCache.remove(_searchCache.keys.first);
      }
      return results;
    });
    _activeSearches[normalized] = future;
    return future.whenComplete(() => _activeSearches.remove(normalized));
  }

  @override
  Future<String?> resolveFriendAvatar(Friend friend) =>
      _hydrateAvatar(friend.avatarStoragePath, friend.avatarUrl);

  @override
  Future<String?> resolveRequestAvatar(FriendRequest request) =>
      _hydrateAvatar(request.peerAvatarStoragePath, request.peerAvatarUrl);

  @override
  Future<String?> resolveCandidateAvatar(FriendCandidate candidate) =>
      _hydrateAvatar(candidate.avatarStoragePath, candidate.avatarUrl);

  @override
  Future<void> sendRequest(FriendCandidate candidate) async {
    final localId = 'local:${_uuid.v4()}';
    await _cache.addRequest(
      FriendRequest(
        id: localId,
        peerId: candidate.id,
        peerUsername: candidate.username,
        peerDisplayName: candidate.displayName,
        peerAvatarUrl: candidate.avatarUrl,
        peerAvatarStoragePath: candidate.avatarStoragePath,
        peerFriendCount: candidate.friendCount,
        direction: FriendRequestDirection.outgoing,
        requestedAt: DateTime.now(),
      ),
    );
    try {
      await _remote.sendRequest(candidate.id);
      _invalidateSearchCache();
      await _synchronize();
    } catch (_) {
      await _cache.removeRequest(localId);
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    final snapshot = await _cache.readRequests();
    final request = snapshot.where((item) => item.id == requestId).firstOrNull;
    await _cache.removeRequest(requestId);
    try {
      await _remote.cancelRequest(requestId);
      _invalidateSearchCache();
    } catch (_) {
      if (request != null) await _cache.addRequest(request);
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<void> respondToRequest(
    String requestId, {
    required bool accept,
  }) async {
    final snapshot = await _cache.readRequests();
    final request = snapshot.where((item) => item.id == requestId).firstOrNull;
    if (accept) {
      await _cache.acceptRequest(requestId);
    } else {
      await _cache.removeRequest(requestId);
    }
    try {
      await _remote.respond(requestId, accept: accept);
      _invalidateSearchCache();
      await _synchronize();
    } catch (_) {
      if (request != null) await _cache.addRequest(request);
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<FriendLocation?> getFriendLocation(String friendId) =>
      _remote.getFriendLocation(friendId);

  @override
  Future<void> pauseRealtime() => _remote.pauseChanges();

  @override
  Future<void> resumeRealtime() async {
    await _ensureStarted();
    await Future.wait([_remote.resumeChanges(), _synchronize()]);
  }

  Future<void> _ensureStarted() async {
    _changesSubscription ??= _remote.watchChanges().listen(
      (_) => unawaited(_synchronizeSafely()),
      onError: (Object error, StackTrace stackTrace) =>
          _config.talker.handle(error, stackTrace, 'Friends stream failed'),
    );
    await _synchronizeSafely();
  }

  Future<void> _synchronize() =>
      _activeSync ??= _performSync().whenComplete(() => _activeSync = null);

  Future<void> _performSync() async {
    final results = await Future.wait([
      _remote.fetchFriends(),
      _remote.fetchRequests(),
    ]);
    await _cache.replaceAll(
      friends: results[0] as List<Friend>,
      requests: results[1] as List<FriendRequest>,
    );
  }

  Future<void> _synchronizeSafely() async {
    try {
      await _synchronize();
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Friends sync failed');
    }
  }

  Future<String?> _hydrateAvatar(String? storagePath, String? remoteUrl) async {
    try {
      if (storagePath != null && storagePath.isNotEmpty) {
        return await _mediaCache.cacheStorageFile(
          ownerUserId: _remote.currentUserId,
          bucket: 'avatars',
          storagePath: storagePath,
          mimeType: 'image/jpeg',
        );
      }
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        return await _mediaCache.cacheNetworkFile(
          ownerUserId: _remote.currentUserId,
          bucket: MediaCacheService.externalAvatarsBucket,
          url: remoteUrl,
        );
      }
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Friend avatar caching failed');
    }
    return null;
  }

  void _invalidateSearchCache() => _searchCache.clear();
}
