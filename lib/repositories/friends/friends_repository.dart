import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/friends/contact_match_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_remote_data_source.dart';

class FriendsRepository
    implements IFriendsRepository, IProfileFriendsRepository {
  static const _locationCacheTtl = Duration(minutes: 10);
  static const _realtimeSyncDebounce = Duration(milliseconds: 250);

  FriendsRepository({
    required AppConfig config,
    required FriendsCacheDataSource cache,
    required ContactMatchCacheDataSource contactMatchCache,
    required FriendsRemoteDataSource remote,
    required MediaCacheService mediaCache,
    required AccountSessionController accountSessionController,
    ContactMatchCachePolicy contactMatchCachePolicy =
        const ContactMatchCachePolicy(),
    DateTime Function()? clock,
  }) : _config = config,
       _cache = cache,
       _contactMatchCache = contactMatchCache,
       _contactMatchCachePolicy = contactMatchCachePolicy,
       _remote = remote,
       _mediaCache = mediaCache,
       _accountSessionController = accountSessionController,
       _clock = clock ?? DateTime.now;

  final AppConfig _config;
  final FriendsCacheDataSource _cache;
  final ContactMatchCacheDataSource _contactMatchCache;
  final ContactMatchCachePolicy _contactMatchCachePolicy;
  final FriendsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final AccountSessionController _accountSessionController;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();
  StreamSubscription<FriendChange>? _changesSubscription;
  DiagnosticsLease? _changesListenerLease;
  AccountSessionSnapshot? _startedScope;
  Timer? _realtimeSyncTimer;
  final StreamController<String> _profileChangesController =
      StreamController<String>.broadcast();
  Future<void>? _activeSync;
  Future<void>? _activePageLoad;
  final Map<String, ({DateTime cachedAt, List<FriendCandidate> results})>
  _searchCache = {};
  final Map<String, Future<List<FriendCandidate>>> _activeSearches = {};
  final Map<String, Future<ContactMatchSnapshot>> _activeContactRefreshes = {};

  static const _manualPhoneSearchCachePolicy = ContactMatchCachePolicy(
    positiveTtl: Duration(seconds: 45),
    negativeTtl: Duration(seconds: 45),
  );
  static const _manualCachePruneInterval = Duration(minutes: 10);
  DateTime? _lastManualCachePruneAt;
  String? _lastManualCachePruneOwnerId;
  final Map<String, Future<FriendLocationLookup>> _activeLocationRequests = {};

  @override
  Stream<List<Friend>> watchPaginatedFriends() {
    final scope = _accountSessionController.capture();
    unawaited(_ensureStarted());
    return _trackLocalStream(
      _cache.watchFriends(ownerUserId: scope.userId),
      'friends-cache',
    );
  }

  @override
  Stream<List<Friend>> watchFriends() {
    final scope = _accountSessionController.capture();
    unawaited(_ensureStarted());
    return _trackLocalStream(
      _cache.watchFriends(ownerUserId: scope.userId),
      'friends-cache',
    );
  }

  @override
  Stream<FriendListCacheState> watchFriendListState() {
    final scope = _accountSessionController.capture();
    unawaited(_ensureStarted());
    return _trackLocalStream(
      _cache.watchFriendListState(ownerUserId: scope.userId),
      'friends-list-state-cache',
    );
  }

  @override
  Stream<List<FriendRequest>> watchRequests() {
    final scope = _accountSessionController.capture();
    unawaited(_ensureStarted());
    return _trackLocalStream(
      _cache.watchRequests(ownerUserId: scope.userId),
      'friend-requests-cache',
    );
  }

  @override
  Stream<List<Friend>> watchCachedFriends() {
    final scope = _accountSessionController.capture();
    return _trackLocalStream(
      _cache.watchFriends(ownerUserId: scope.userId),
      'friends-cache',
    );
  }

  @override
  Stream<List<FriendRequest>> watchCachedRequests() {
    final scope = _accountSessionController.capture();
    return _trackLocalStream(
      _cache.watchRequests(ownerUserId: scope.userId),
      'friend-requests-cache',
    );
  }

  @override
  Stream<String> watchProfileChanges() {
    unawaited(_ensureStarted());
    return _trackLocalStream(
      _profileChangesController.stream,
      'friend-profile-changes',
    );
  }

  Stream<T> _trackLocalStream<T>(Stream<T> source, String owner) {
    return Stream.multi((controller) {
      final lease = _config.diagnostics?.trackLocalListener(owner);
      final subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await subscription.cancel();
        lease?.dispose();
      };
    });
  }

  @override
  Future<void> loadMoreFriends() async {
    final active = _activePageLoad;
    if (active != null) return active;
    final load = _performLoadMoreFriends();
    _activePageLoad = load;
    return load.whenComplete(() {
      if (identical(_activePageLoad, load)) _activePageLoad = null;
    });
  }

  @override
  Future<List<FriendRequest>> getRequests() async {
    final scope = _accountSessionController.capture();
    await _synchronize();
    _accountSessionController.ensureCurrent(scope);
    return _cache.readRequests(ownerUserId: scope.userId);
  }

  @override
  Future<List<FriendCandidate>> searchUsers(String query) async {
    final scope = _accountSessionController.capture();
    final normalized = query.trim().toLowerCase();
    final operationKey = _operationKey(scope, normalized);
    final cached = _searchCache[operationKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) <
            const Duration(seconds: 45)) {
      return cached.results;
    }
    final active = _activeSearches[operationKey];
    if (active != null) return active;
    final future = _remote.searchUsers(normalized).then((results) async {
      _accountSessionController.ensureCurrent(scope);
      await _cacheFriendsFoundBySearchSafely(results, scope);
      _searchCache[operationKey] = (cachedAt: DateTime.now(), results: results);
      while (_searchCache.length > 20) {
        _searchCache.remove(_searchCache.keys.first);
      }
      return results;
    });
    _activeSearches[operationKey] = future;
    return future.whenComplete(() => _activeSearches.remove(operationKey));
  }

  @override
  Future<ContactMatchSnapshot> readCachedContactMatches(
    List<String> phoneNumbers,
  ) async {
    final scope = _accountSessionController.capture();
    final unique = phoneNumbers.toSet().toList(growable: false);
    final records = await _contactMatchCache.read(
      unique,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    await _cacheFriendsFoundBySearchSafely(
      records.values
          .map((record) => record.candidate)
          .whereType<FriendCandidate>(),
      scope,
    );
    final snapshot = await _buildContactSnapshot(
      records,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return snapshot;
  }

  @override
  Future<ContactMatchSnapshot> readCachedPhoneSearchMatch(
    String phoneNumber,
  ) async {
    final scope = _accountSessionController.capture();
    final normalized = phoneNumber.trim();
    if (normalized.isEmpty) return const ContactMatchSnapshot();
    final records = await _contactMatchCache.read(
      [normalized],
      ownerUserId: scope.userId,
      scope: PhoneMatchCacheScope.manualSearch,
    );
    _accountSessionController.ensureCurrent(scope);
    final record = records[normalized];
    if (_manualPhoneSearchCachePolicy.shouldRefresh(record, _clock().toUtc())) {
      return const ContactMatchSnapshot();
    }
    await _cacheFriendsFoundBySearchSafely(
      records.values
          .map((cachedRecord) => cachedRecord.candidate)
          .whereType<FriendCandidate>(),
      scope,
    );
    final snapshot = await _buildContactSnapshot(
      records,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return snapshot;
  }

  @override
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  ) {
    final scope = _accountSessionController.capture();
    final unique = phoneNumbers.toSet().toList(growable: false)..sort();
    final operationKey = _operationKey(scope, unique.join('\u0000'));
    final active = _activeContactRefreshes[operationKey];
    if (active != null) return active;
    final future = _refreshContactMatches(
      unique,
      retainOnlyInput: true,
      scope: scope,
    );
    _activeContactRefreshes[operationKey] = future;
    return future.whenComplete(
      () => _activeContactRefreshes.remove(operationKey),
    );
  }

  @override
  Future<ContactMatchSnapshot> refreshNewFriendContactMatches(
    List<String> phoneNumbers,
    Set<String> friendIds,
  ) async {
    final scope = _accountSessionController.capture();
    final uniquePhones = phoneNumbers.toSet().toList(growable: false)..sort();
    final uniqueFriendIds = friendIds.toList(growable: false)..sort();
    if (uniquePhones.isEmpty || uniqueFriendIds.isEmpty) {
      return readCachedContactMatches(uniquePhones);
    }
    final operationKey = _operationKey(
      scope,
      'new-friend-contacts:${uniqueFriendIds.join('\u0000')}:${uniquePhones.join('\u0000')}',
    );
    final active = _activeContactRefreshes[operationKey];
    if (active != null) return active;
    final future = _refreshNewFriendContactMatches(
      uniquePhones,
      uniqueFriendIds,
      scope,
    );
    _activeContactRefreshes[operationKey] = future;
    return future.whenComplete(
      () => _activeContactRefreshes.remove(operationKey),
    );
  }

  @override
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phoneNumber) {
    final scope = _accountSessionController.capture();
    final normalized = phoneNumber.trim();
    if (normalized.isEmpty) return Future.value(const ContactMatchSnapshot());
    final operationKey = _operationKey(scope, 'manual-phone:$normalized');
    final active = _activeContactRefreshes[operationKey];
    if (active != null) return active;
    final future = _refreshManualPhoneMatch(normalized, scope);
    _activeContactRefreshes[operationKey] = future;
    return future.whenComplete(
      () => _activeContactRefreshes.remove(operationKey),
    );
  }

  Future<ContactMatchSnapshot> _refreshManualPhoneMatch(
    String phoneNumber,
    AccountSessionSnapshot scope,
  ) async {
    final now = _clock().toUtc();
    final lastPruneAt = _lastManualCachePruneAt;
    if (_lastManualCachePruneOwnerId != scope.userId ||
        lastPruneAt == null ||
        now.difference(lastPruneAt) >= _manualCachePruneInterval) {
      await _accountSessionController.commit(
        scope,
        () => _contactMatchCache.pruneExpiredManualSearchMatches(
          expiredBefore: now.subtract(
            _manualPhoneSearchCachePolicy.positiveTtl,
          ),
          ownerUserId: scope.userId,
        ),
      );
      _lastManualCachePruneAt = now;
      _lastManualCachePruneOwnerId = scope.userId;
    }
    return _refreshContactMatches(
      [phoneNumber],
      retainOnlyInput: false,
      scope: scope,
      cacheScope: PhoneMatchCacheScope.manualSearch,
      cachePolicy: _manualPhoneSearchCachePolicy,
    );
  }

  Future<ContactMatchSnapshot> _refreshNewFriendContactMatches(
    List<String> phoneNumbers,
    List<String> friendIds,
    AccountSessionSnapshot scope,
  ) async {
    const phoneBatchSize = 500;
    const friendBatchSize = 100;
    final matches = <String, FriendCandidate>{};
    for (
      var phoneOffset = 0;
      phoneOffset < phoneNumbers.length;
      phoneOffset += phoneBatchSize
    ) {
      final phoneEnd = (phoneOffset + phoneBatchSize).clamp(
        0,
        phoneNumbers.length,
      );
      for (
        var friendOffset = 0;
        friendOffset < friendIds.length;
        friendOffset += friendBatchSize
      ) {
        final friendEnd = (friendOffset + friendBatchSize).clamp(
          0,
          friendIds.length,
        );
        matches.addAll(
          await _remote.matchNewFriendContactPhones(
            phoneNumbers.sublist(phoneOffset, phoneEnd),
            friendIds.sublist(friendOffset, friendEnd),
          ),
        );
        _accountSessionController.ensureCurrent(scope);
      }
    }
    if (matches.isNotEmpty) {
      await _cacheFriendsFoundBySearchSafely(matches.values, scope);
      await _accountSessionController.commit(
        scope,
        () => _contactMatchCache.writeMatches(
          matches: matches,
          checkedAt: _clock().toUtc(),
          ownerUserId: scope.userId,
        ),
      );
    }
    final records = await _contactMatchCache.read(
      phoneNumbers,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    final snapshot = await _buildContactSnapshot(
      records,
      freshMatches: matches,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return snapshot;
  }

  Future<ContactMatchSnapshot> _refreshContactMatches(
    List<String> phoneNumbers, {
    required bool retainOnlyInput,
    required AccountSessionSnapshot scope,
    PhoneMatchCacheScope cacheScope = PhoneMatchCacheScope.contacts,
    ContactMatchCachePolicy? cachePolicy,
  }) async {
    const batchSize = 500;
    if (retainOnlyInput) {
      await _accountSessionController.commit(
        scope,
        () => _contactMatchCache.retainOnly(
          phoneNumbers,
          ownerUserId: scope.userId,
          scope: cacheScope,
        ),
      );
    }
    final cached = await _contactMatchCache.read(
      phoneNumbers,
      ownerUserId: scope.userId,
      scope: cacheScope,
    );
    _accountSessionController.ensureCurrent(scope);
    final now = _clock().toUtc();
    final stalePhoneNumbers = phoneNumbers
        .where(
          (phone) => (cachePolicy ?? _contactMatchCachePolicy).shouldRefresh(
            cached[phone],
            now,
          ),
        )
        .toList(growable: false);

    final freshMatches = <String, FriendCandidate>{};
    for (
      var offset = 0;
      offset < stalePhoneNumbers.length;
      offset += batchSize
    ) {
      final end = (offset + batchSize).clamp(0, stalePhoneNumbers.length);
      freshMatches.addAll(
        await _remote.matchContactPhones(
          stalePhoneNumbers.sublist(offset, end),
        ),
      );
      _accountSessionController.ensureCurrent(scope);
    }
    await _cacheFriendsFoundBySearchSafely(freshMatches.values, scope);
    if (stalePhoneNumbers.isNotEmpty) {
      await _accountSessionController.commit(
        scope,
        () => _contactMatchCache.writeResults(
          checkedPhoneNumbers: stalePhoneNumbers,
          matches: freshMatches,
          checkedAt: now,
          ownerUserId: scope.userId,
          scope: cacheScope,
        ),
      );
    }
    final updated = await _contactMatchCache.read(
      phoneNumbers,
      ownerUserId: scope.userId,
      scope: cacheScope,
    );
    _accountSessionController.ensureCurrent(scope);
    final snapshot = await _buildContactSnapshot(
      updated,
      freshMatches: freshMatches,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return snapshot;
  }

  Future<ContactMatchSnapshot> _buildContactSnapshot(
    Map<String, ContactMatchCacheRecord> records, {
    Map<String, FriendCandidate> freshMatches = const {},
    required String ownerUserId,
  }) async {
    final friends = await _cache.readFriends(ownerUserId: ownerUserId);
    final requests = await _cache.readRequests(ownerUserId: ownerUserId);
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
          : candidate.relationship;
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

  Future<void> _cacheFriendsFoundBySearch(
    Iterable<FriendCandidate> candidates,
    AccountSessionSnapshot scope,
  ) async {
    final ids = candidates
        .where(
          (candidate) => candidate.relationship == FriendRelationship.friend,
        )
        .map((candidate) => candidate.id)
        .toSet();
    if (ids.isEmpty) return;

    final cached = await _cache.readFriends(ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    ids.removeAll(cached.map((friend) => friend.id));
    if (ids.isEmpty) return;

    const batchSize = 500;
    final foundFriends = <Friend>[];
    final pendingIds = ids.toList(growable: false);
    for (var offset = 0; offset < pendingIds.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, pendingIds.length);
      foundFriends.addAll(
        await _remote.fetchCurrentFriends(pendingIds.sublist(offset, end)),
      );
      _accountSessionController.ensureCurrent(scope);
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.cacheFoundFriends(foundFriends, ownerUserId: scope.userId),
    );
  }

  Future<void> _cacheFriendsFoundBySearchSafely(
    Iterable<FriendCandidate> candidates,
    AccountSessionSnapshot scope,
  ) async {
    try {
      await _cacheFriendsFoundBySearch(candidates, scope);
    } on StaleAccountSessionException {
      rethrow;
    } catch (error, stackTrace) {
      // A search result remains valid even when the optional cache extension
      // is temporarily unavailable (for example, while reconnecting).
      _config.talker.handle(
        error,
        stackTrace,
        'Searched friend cache extension failed',
      );
    }
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
    final scope = _accountSessionController.capture();
    final localId = 'local:${_uuid.v4()}';
    await _accountSessionController.commit(
      scope,
      () => _cache.addRequest(
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
        ownerUserId: scope.userId,
      ),
    );
    try {
      _accountSessionController.ensureCurrent(scope);
      await _remote.sendRequest(candidate.id);
      _accountSessionController.ensureCurrent(scope);
      _invalidateSearchCache();
      await _synchronize();
    } on StaleAccountSessionException {
      return;
    } catch (_) {
      await _accountSessionController.commit(
        scope,
        () => _cache.removeRequest(localId, ownerUserId: scope.userId),
      );
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    final scope = _accountSessionController.capture();
    final snapshot = await _cache.readRequests(ownerUserId: scope.userId);
    final request = snapshot.where((item) => item.id == requestId).firstOrNull;
    await _accountSessionController.commit(
      scope,
      () => _cache.removeRequest(requestId, ownerUserId: scope.userId),
    );
    try {
      _accountSessionController.ensureCurrent(scope);
      await _remote.cancelRequest(requestId);
      _accountSessionController.ensureCurrent(scope);
      _invalidateSearchCache();
    } on StaleAccountSessionException {
      return;
    } catch (_) {
      if (request != null) {
        await _accountSessionController.commit(
          scope,
          () => _cache.addRequest(request, ownerUserId: scope.userId),
        );
      }
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<void> respondToRequest(
    String requestId, {
    required bool accept,
  }) async {
    final scope = _accountSessionController.capture();
    final snapshot = await _cache.readRequests(ownerUserId: scope.userId);
    final request = snapshot.where((item) => item.id == requestId).firstOrNull;
    await _accountSessionController.commit(scope, () async {
      if (accept) {
        await _cache.acceptRequest(requestId, ownerUserId: scope.userId);
      } else {
        await _cache.removeRequest(requestId, ownerUserId: scope.userId);
      }
    });
    try {
      _accountSessionController.ensureCurrent(scope);
      await _remote.respond(requestId, accept: accept);
      _accountSessionController.ensureCurrent(scope);
      _invalidateSearchCache();
      await _synchronize();
    } on StaleAccountSessionException {
      return;
    } catch (_) {
      if (request != null) {
        await _accountSessionController.commit(
          scope,
          () => _cache.addRequest(request, ownerUserId: scope.userId),
        );
      }
      await _synchronizeSafely();
      rethrow;
    }
  }

  @override
  Future<FriendLocationLookup> getFriendLocation(String friendId) async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readLocation(
      friendId,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    if (cached != null && _isLocationTimestampCurrent(cached.updatedAt)) {
      final isFresh = await _cache.hasFreshLocation(
        friendId,
        maxAge: _locationCacheTtl,
        ownerUserId: scope.userId,
      );
      if (!isFresh) {
        unawaited(_refreshFriendLocationSafely(friendId, scope));
      }
      return FriendLocationLookup.current(cached);
    }
    if (cached != null) {
      await _accountSessionController.commit(
        scope,
        () => _cache.removeLocation(friendId, ownerUserId: scope.userId),
      );
    }
    return _refreshFriendLocation(friendId, scope);
  }

  @override
  Future<FriendLocation?> getCachedFriendLocation(String friendId) async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readLocation(
      friendId,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    if (cached == null || _isLocationTimestampCurrent(cached.updatedAt)) {
      return cached;
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.removeLocation(friendId, ownerUserId: scope.userId),
    );
    return null;
  }

  @override
  Future<UserDistance?> getCachedUserDistance(String userId) async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readDistance(userId, ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    if (cached == null || _isLocationTimestampCurrent(cached.updatedAt)) {
      return cached;
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.removeDistance(userId, ownerUserId: scope.userId),
    );
    return null;
  }

  @override
  Future<bool> isCachedUserDistanceFresh(String userId) async {
    final scope = _accountSessionController.capture();
    final cached = await getCachedUserDistance(userId);
    if (cached == null) return false;
    return _cache.hasFreshDistance(
      userId,
      maxAge: _locationCacheTtl,
      ownerUserId: scope.userId,
    );
  }

  @override
  Future<void> cacheUserDistance(String userId, UserDistance distance) async {
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.writeDistance(userId, distance, ownerUserId: scope.userId),
    );
  }

  @override
  Future<void> clearCachedUserDistances() async {
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.clearDistances(ownerUserId: scope.userId),
    );
  }

  @override
  Future<UserDistance?> getUserDistance(String userId) async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readDistance(userId, ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    if (cached != null &&
        _isLocationTimestampCurrent(cached.updatedAt) &&
        await _cache.hasFreshDistance(
          userId,
          maxAge: _locationCacheTtl,
          ownerUserId: scope.userId,
        )) {
      return cached;
    }
    try {
      final distance = await _remote.getUserDistance(userId);
      await _accountSessionController.commit(scope, () async {
        if (distance == null) {
          await _cache.removeDistance(userId, ownerUserId: scope.userId);
        } else {
          await _cache.writeDistance(
            userId,
            distance,
            ownerUserId: scope.userId,
          );
        }
      });
      return distance;
    } catch (_) {
      _accountSessionController.ensureCurrent(scope);
      final fallback = await _cache.readDistance(
        userId,
        ownerUserId: scope.userId,
      );
      if (fallback != null && _isLocationTimestampCurrent(fallback.updatedAt)) {
        return fallback;
      }
      rethrow;
    }
  }

  @override
  Future<void> removeFriend(String friendId) async {
    final scope = _accountSessionController.capture();
    final previous = await _cache.readFriends(ownerUserId: scope.userId);
    final previousRequests = await _cache.readRequests(
      ownerUserId: scope.userId,
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.removeFriend(friendId, ownerUserId: scope.userId),
    );
    try {
      await _remote.removeFriend(friendId);
      _accountSessionController.ensureCurrent(scope);
      _invalidateSearchCache();
      await _synchronize();
    } catch (_) {
      await _accountSessionController.commit(
        scope,
        () => _cache.replaceAll(
          ownerUserId: scope.userId,
          friends: previous,
          requests: previousRequests,
        ),
      );
      await _synchronizeSafely();
      rethrow;
    }
  }

  Future<FriendLocationLookup> _refreshFriendLocation(
    String friendId,
    AccountSessionSnapshot scope,
  ) {
    final operationKey = _operationKey(scope, friendId);
    final active = _activeLocationRequests[operationKey];
    if (active != null) return active;
    final future = _remote.getFriendLocation(friendId).then((lookup) async {
      await _accountSessionController.commit(scope, () async {
        final location = lookup.location;
        if (lookup.availability == FriendLocationAvailability.unavailable) {
          await _cache.removeLocation(friendId, ownerUserId: scope.userId);
        } else if (location != null) {
          await _cache.writeLocation(
            friendId,
            location,
            ownerUserId: scope.userId,
          );
        }
      });
      return lookup;
    });
    _activeLocationRequests[operationKey] = future;
    return future.whenComplete(
      () => _activeLocationRequests.remove(operationKey),
    );
  }

  Future<void> _refreshFriendLocationSafely(
    String friendId,
    AccountSessionSnapshot scope,
  ) async {
    try {
      await _refreshFriendLocation(friendId, scope);
    } on StaleAccountSessionException {
      return;
    } catch (error, stackTrace) {
      _config.talker.handle(
        error,
        stackTrace,
        'Friend location refresh failed',
      );
    }
  }

  bool _isLocationTimestampCurrent(DateTime updatedAt) {
    final age = DateTime.now().toUtc().difference(updatedAt.toUtc());
    return !age.isNegative && age < const Duration(hours: 24);
  }

  @override
  Future<void> pauseRealtime() {
    _activeSync = null;
    _activePageLoad = null;
    _searchCache.clear();
    _activeSearches.clear();
    _activeContactRefreshes.clear();
    _activeLocationRequests.clear();
    _realtimeSyncTimer?.cancel();
    _realtimeSyncTimer = null;
    return _remote.pauseChanges();
  }

  @override
  Future<void> resumeRealtime() async {
    await _ensureStarted(forceSync: true);
    await _remote.resumeChanges();
  }

  Future<void> _ensureStarted({bool forceSync = false}) async {
    final scope = _accountSessionController.capture();
    final startedScope = _startedScope;
    final isCurrentScope =
        startedScope != null &&
        startedScope.userId == scope.userId &&
        startedScope.generation == scope.generation;
    if (isCurrentScope && !forceSync) return;

    _startedScope = scope;
    _changesSubscription ??= _remote.watchChanges().listen(
      (change) {
        final profileId = change.profileId;
        if (profileId != null && !_profileChangesController.isClosed) {
          _profileChangesController.add(profileId);
        }
        _handleRealtimeChange(change);
      },
      onError: (Object error, StackTrace stackTrace) =>
          _config.talker.handle(error, stackTrace, 'Friends stream failed'),
    );
    _changesListenerLease ??= _config.diagnostics?.trackLocalListener(
      'friends-realtime-events',
    );
    await _synchronizeSafely();
  }

  void _handleRealtimeChange(FriendChange change) {
    final profileId = change.profileId;
    if (profileId == null) {
      _scheduleRealtimeSync();
      return;
    }

    // This event is emitted only for identity fields. Updating the one cached
    // record preserves pages that are already available offline; a head-page
    // refresh alone would leave a later cached page stale.
    if (change.reason == 'profile_updated') {
      unawaited(_refreshCachedFriend(profileId));
      return;
    }

    final friendshipWasRemoved =
        change.table == 'friendships' && change.operation == 'DELETE';
    final peerWasBlocked =
        change.reason == 'block' && change.action == 'blocked';
    if (friendshipWasRemoved || peerWasBlocked) {
      final scope = _accountSessionController.capture();
      unawaited(
        _accountSessionController.commit(
          scope,
          () => _cache.updateFriendFromRealtime(
            null,
            friendId: profileId,
            ownerUserId: scope.userId,
          ),
        ),
      );
    }
    _scheduleRealtimeSync();
  }

  Future<void> _refreshCachedFriend(String friendId) async {
    final scope = _accountSessionController.capture();
    try {
      final isCached = await _cache.containsFriend(
        friendId,
        ownerUserId: scope.userId,
      );
      _accountSessionController.ensureCurrent(scope);
      if (!isCached) return;
      final friend = await _remote.fetchCurrentFriend(friendId);
      await _accountSessionController.commit(
        scope,
        () => _cache.updateFriendFromRealtime(
          friend,
          friendId: friendId,
          ownerUserId: scope.userId,
        ),
      );
    } on StaleAccountSessionException {
      return;
    } catch (error, stackTrace) {
      _config.talker.handle(
        error,
        stackTrace,
        'Cached friend realtime refresh failed',
      );
      // The normal coalesced sync will recover from a transient RPC failure.
      _scheduleRealtimeSync();
    }
  }

  void _scheduleRealtimeSync() {
    if (_realtimeSyncTimer != null) return;
    _realtimeSyncTimer = Timer(_realtimeSyncDebounce, () {
      _realtimeSyncTimer = null;
      unawaited(_synchronizeSafely());
    });
  }

  Future<void> _synchronize() {
    final active = _activeSync;
    if (active != null) return active;
    final sync =
        _config.diagnostics?.measureSync('friends', _performSync) ??
        _performSync();
    _activeSync = sync;
    return sync.whenComplete(() {
      if (identical(_activeSync, sync)) _activeSync = null;
    });
  }

  Future<void> _performSync() async {
    final scope = _accountSessionController.capture();
    final results = await Future.wait([
      _remote.fetchFriendsPage(),
      _remote.fetchRequests(),
    ]);
    await _accountSessionController.commit(scope, () async {
      await _cache.replaceFriendListHead(
        results[0] as FriendPage,
        ownerUserId: scope.userId,
      );
      await _cache.replaceRequests(
        results[1] as List<FriendRequest>,
        ownerUserId: scope.userId,
      );
    });
    _config.diagnostics?.recordSyncItems(
      'friends',
      (results[0] as FriendPage).friends.length +
          (results[1] as List<FriendRequest>).length,
    );
  }

  Future<void> _performLoadMoreFriends() async {
    final scope = _accountSessionController.capture();
    final state = await _cache.readFriendListState(ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    final cursor = state.nextCursor;
    if (!state.hasMore || cursor == null) return;
    final page =
        await (_config.diagnostics?.measureSync(
              'friends-page',
              () => _remote.fetchFriendsPage(after: cursor),
            ) ??
            _remote.fetchFriendsPage(after: cursor));
    await _accountSessionController.commit(
      scope,
      () => _cache.appendFriendPage(page, ownerUserId: scope.userId),
    );
    _config.diagnostics?.recordSyncItems('friends-page', page.friends.length);
  }

  Future<void> _synchronizeSafely() async {
    try {
      await _synchronize();
    } on StaleAccountSessionException {
      return;
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Friends sync failed');
    }
  }

  Future<String?> _hydrateAvatar(String? storagePath, String? remoteUrl) async {
    final scope = _accountSessionController.capture();
    try {
      if (storagePath != null && storagePath.isNotEmpty) {
        final result = await _mediaCache.cacheStorageFile(
          ownerUserId: scope.userId,
          bucket: 'avatars',
          storagePath: storagePath,
          mimeType: 'image/jpeg',
        );
        _accountSessionController.ensureCurrent(scope);
        return result;
      }
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        final result = await _mediaCache.cacheNetworkFile(
          ownerUserId: scope.userId,
          bucket: MediaCacheService.externalAvatarsBucket,
          url: remoteUrl,
        );
        _accountSessionController.ensureCurrent(scope);
        return result;
      }
    } on StaleAccountSessionException {
      return null;
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Friend avatar caching failed');
    }
    return null;
  }

  String _operationKey(AccountSessionSnapshot scope, String value) =>
      '${scope.generation}\u0000${scope.userId}\u0000$value';

  void _invalidateSearchCache() => _searchCache.clear();
}
