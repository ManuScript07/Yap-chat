import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/friends/contact_match_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_remote_data_source.dart';

class FriendsRepository implements IFriendsRepository {
  FriendsRepository({
    required AppConfig config,
    required FriendsCacheDataSource cache,
    required ContactMatchCacheDataSource contactMatchCache,
    required FriendsRemoteDataSource remote,
    required MediaCacheService mediaCache,
    ContactMatchCachePolicy contactMatchCachePolicy =
        const ContactMatchCachePolicy(),
    DateTime Function()? clock,
  }) : _config = config,
       _cache = cache,
       _contactMatchCache = contactMatchCache,
       _contactMatchCachePolicy = contactMatchCachePolicy,
       _remote = remote,
       _mediaCache = mediaCache,
       _clock = clock ?? DateTime.now;

  final AppConfig _config;
  final FriendsCacheDataSource _cache;
  final ContactMatchCacheDataSource _contactMatchCache;
  final ContactMatchCachePolicy _contactMatchCachePolicy;
  final FriendsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();
  StreamSubscription<void>? _changesSubscription;
  Future<void>? _activeSync;
  final Map<String, ({DateTime cachedAt, List<FriendCandidate> results})>
  _searchCache = {};
  final Map<String, Future<List<FriendCandidate>>> _activeSearches = {};
  final Map<String, Future<ContactMatchSnapshot>> _activeContactRefreshes = {};

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
  Future<ContactMatchSnapshot> readCachedContactMatches(
    List<String> phoneNumbers,
  ) async {
    final unique = phoneNumbers.toSet().toList(growable: false);
    final records = await _contactMatchCache.read(unique);
    return _buildContactSnapshot(records);
  }

  @override
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  ) {
    final unique = phoneNumbers.toSet().toList(growable: false)..sort();
    final operationKey = unique.join('\u0000');
    final active = _activeContactRefreshes[operationKey];
    if (active != null) return active;
    final future = _refreshContactMatches(unique);
    _activeContactRefreshes[operationKey] = future;
    return future.whenComplete(
      () => _activeContactRefreshes.remove(operationKey),
    );
  }

  Future<ContactMatchSnapshot> _refreshContactMatches(
    List<String> phoneNumbers,
  ) async {
    const batchSize = 500;
    await _contactMatchCache.retainOnly(phoneNumbers);
    final cached = await _contactMatchCache.read(phoneNumbers);
    final now = _clock().toUtc();
    final stalePhoneNumbers = phoneNumbers
        .where(
          (phone) =>
              _contactMatchCachePolicy.shouldRefresh(cached[phone], now),
        )
        .toList(growable: false);

    final freshMatches = <String, FriendCandidate>{};
    for (var offset = 0; offset < stalePhoneNumbers.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, stalePhoneNumbers.length);
      freshMatches.addAll(
        await _remote.matchContactPhones(
          stalePhoneNumbers.sublist(offset, end),
        ),
      );
    }
    if (stalePhoneNumbers.isNotEmpty) {
      await _contactMatchCache.writeResults(
        checkedPhoneNumbers: stalePhoneNumbers,
        matches: freshMatches,
        checkedAt: now,
      );
    }
    final updated = await _contactMatchCache.read(phoneNumbers);
    return _buildContactSnapshot(updated, freshMatches: freshMatches);
  }

  Future<ContactMatchSnapshot> _buildContactSnapshot(
    Map<String, ContactMatchCacheRecord> records, {
    Map<String, FriendCandidate> freshMatches = const {},
  }) async {
    final friends = await _cache.readFriends();
    final requests = await _cache.readRequests();
    final friendsById = {for (final friend in friends) friend.id: friend};
    final requestsByPeerId = {
      for (final request in requests) request.peerId: request,
    };
    final matches = <String, FriendCandidate>{};
    for (final entry in records.entries) {
      final cachedCandidate = entry.value.candidate;
      if (!entry.value.isRegistered || cachedCandidate == null) continue;
      final freshCandidate = freshMatches[entry.key];
      final candidate = freshCandidate ?? cachedCandidate;
      final friend = friendsById[candidate.id];
      final request = requestsByPeerId[candidate.id];
      final relationship = friend != null
          ? FriendRelationship.friend
          : request != null
          ? request.direction == FriendRequestDirection.incoming
                ? FriendRelationship.incoming
                : FriendRelationship.outgoing
          : freshCandidate?.relationship ?? FriendRelationship.none;
      matches[entry.key] = FriendCandidate(
        id: candidate.id,
        requestId: request?.id ?? freshCandidate?.requestId,
        username: candidate.username,
        displayName: candidate.displayName,
        avatarUrl: candidate.avatarUrl,
        avatarStoragePath: candidate.avatarStoragePath,
        friendCount: candidate.friendCount,
        relationship: relationship,
      );
    }
    return ContactMatchSnapshot(
      matches: Map.unmodifiable(matches),
      checkedPhoneNumbers: Set.unmodifiable(records.keys),
    );
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
