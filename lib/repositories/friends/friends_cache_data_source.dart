import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/friends/data/data.dart';

class FriendsCacheDataSource {
  const FriendsCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
    MediaCacheService? mediaCache,
  }) : _database = database,
       _userIdProvider = userIdProvider,
       _mediaCache = mediaCache;

  final AppDatabase _database;
  final String Function() _userIdProvider;
  final MediaCacheService? _mediaCache;

  static const _friendTimeOrder = CustomExpression<int>(
    'COALESCE(friends_since_micros, friends_since * 1000000)',
  );

  Future<void> _prepareAvatarPaths() async {
    try {
      await _mediaCache?.prepareLocalPaths();
    } catch (_) {
      // Cache-directory failure is not a failure to load the friends list.
    }
  }

  Stream<List<Friend>> watchFriends({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriends)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([
        (_) => OrderingTerm.desc(_friendTimeOrder),
        (table) => OrderingTerm.desc(table.userId),
      ]);
    final pathsReady = _prepareAvatarPaths();
    return query.watch().asyncMap((rows) async {
      await pathsReady;
      return List.unmodifiable(rows.map(_mapFriend));
    });
  }

  Stream<List<FriendRequest>> watchRequests({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriendRequests)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.requestedAt)]);
    return query.watch().map(
      (rows) => List.unmodifiable(rows.map(_mapRequest)),
    );
  }

  Future<List<Friend>> readFriends({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriends)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([
        (_) => OrderingTerm.desc(_friendTimeOrder),
        (table) => OrderingTerm.desc(table.userId),
      ]);
    final pathsReady = _prepareAvatarPaths();
    final rows = await query.get();
    await pathsReady;
    return rows.map(_mapFriend).toList(growable: false);
  }

  Future<bool> containsFriend(String friendId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.selectOnly(_database.cachedFriends)
      ..addColumns([_database.cachedFriends.userId])
      ..where(
        _database.cachedFriends.ownerUserId.equals(owner) &
            _database.cachedFriends.userId.equals(friendId),
      )
      ..limit(1);
    return await query.getSingleOrNull() != null;
  }

  Stream<FriendListCacheState> watchFriendListState({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriendListStates)
      ..where((table) => table.ownerUserId.equals(owner));
    return query.watchSingleOrNull().asyncMap(
      (row) => row == null
          ? _deriveFriendListState(owner)
          : Future.value(_mapFriendListState(row)),
    );
  }

  Future<FriendListCacheState> readFriendListState({
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row = await (_database.select(
      _database.cachedFriendListStates,
    )..where((table) => table.ownerUserId.equals(owner))).getSingleOrNull();
    return row == null
        ? _deriveFriendListState(owner)
        : _mapFriendListState(row);
  }

  Future<void> replaceFriendListHead(
    FriendPage page, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      final previousFriends = await readFriends(ownerUserId: owner);
      final previousState = await readFriendListState(ownerUserId: owner);
      final previousCount = previousFriends.length;
      // A first cursor page is authoritative for its own range. Preserve
      // cached rows behind that range for offline pagination, but remove a
      // locally optimistic row when the server proves it cannot be there.
      // Without this reconciliation, a failed concurrent request acceptance
      // could leave a non-existent newest friend in the local list forever.
      await _removeFriendsAbsentFromAuthoritativeHead(
        owner: owner,
        cachedFriends: previousFriends,
        page: page,
      );
      await _upsertFriends(page.friends, owner);
      final cachedCount = await _countFriends(owner);
      final restarting =
          !previousState.isAuthoritative ||
          previousCount <= page.friends.length ||
          (previousState.requiresCursorRepair &&
              previousState.nextCursor == null);
      // Legacy rows may already fill totalCount while hiding gaps, so repair
      // must follow server coverage rather than treating row count as proof.
      final hasMore =
          page.hasMore &&
          (restarting || previousState.hasMore) &&
          (previousState.requiresCursorRepair || cachedCount < page.totalCount);
      final nextCursor = !hasMore
          ? null
          : restarting
          ? page.nextCursor
          : previousState.nextCursor;
      await _writeFriendListState(
        owner: owner,
        cursor: nextCursor,
        hasMore: hasMore,
        totalCount: page.totalCount,
        requiresCursorRepair: previousState.requiresCursorRepair && hasMore,
      );
    });
  }

  Future<void> _removeFriendsAbsentFromAuthoritativeHead({
    required String owner,
    required List<Friend> cachedFriends,
    required FriendPage page,
  }) async {
    if (cachedFriends.isEmpty) return;
    final incomingIds = page.friends.map((friend) => friend.id).toSet();

    // A short first page is the entire authoritative list. This also covers
    // the empty result where a successful RPC has no row to carry total_count.
    final completeSnapshot = page.friends.length >= page.totalCount;
    final headBoundary = page.friends.lastOrNull;
    final staleIds = cachedFriends
        .where(
          (friend) =>
              !incomingIds.contains(friend.id) &&
              (completeSnapshot ||
                  (headBoundary != null &&
                      _isAtOrAheadOfHead(friend, headBoundary))),
        )
        .map((friend) => friend.id)
        .toList(growable: false);
    if (staleIds.isEmpty) return;

    await (_database.delete(_database.cachedFriends)..where(
          (table) =>
              table.ownerUserId.equals(owner) & table.userId.isIn(staleIds),
        ))
        .go();
  }

  bool _isAtOrAheadOfHead(Friend candidate, Friend boundary) {
    final byTimestamp = candidate.friendsSince.compareTo(boundary.friendsSince);
    if (byTimestamp != 0) return byTimestamp > 0;
    return candidate.id.compareTo(boundary.id) >= 0;
  }

  Future<void> appendFriendPage(FriendPage page, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      final previousState = await readFriendListState(ownerUserId: owner);
      await _upsertFriends(page.friends, owner);
      final cachedCount = await _countFriends(owner);
      final hasMore =
          page.hasMore &&
          (previousState.requiresCursorRepair || cachedCount < page.totalCount);
      await _writeFriendListState(
        owner: owner,
        cursor: hasMore ? page.nextCursor : null,
        hasMore: hasMore,
        totalCount: page.totalCount,
        requiresCursorRepair:
            previousState.requiresCursorRepair && page.hasMore,
      );
    });
  }

  Future<void> updateFriendFromRealtime(
    Friend? friend, {
    required String friendId,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      if (friend == null) {
        await removeFriend(friendId, ownerUserId: owner);
      } else {
        await _database
            .into(_database.cachedFriends)
            .insertOnConflictUpdate(_friendRow(friend, owner));
      }
    });
  }

  /// Extends the local list with friends discovered by a trusted server-side
  /// search. It deliberately does not change cursor metadata: a subsequent
  /// cursor page may contain the same row and is safely upserted.
  Future<void> cacheFoundFriends(
    List<Friend> friends, {
    String? ownerUserId,
  }) async {
    if (friends.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      final state = await readFriendListState(ownerUserId: owner);
      await _upsertFriends(friends, owner);
      final cachedCount = await _countFriends(owner);
      if (!state.requiresCursorRepair &&
          state.hasMore &&
          state.totalCount > 0 &&
          cachedCount >= state.totalCount) {
        await _writeFriendListState(
          owner: owner,
          cursor: null,
          hasMore: false,
          totalCount: state.totalCount,
        );
      }
    });
  }

  Future<int> _countFriends(String owner) async {
    final count = _database.cachedFriends.userId.count();
    final query = _database.selectOnly(_database.cachedFriends)
      ..addColumns([count])
      ..where(_database.cachedFriends.ownerUserId.equals(owner));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<FriendListCacheState> _deriveFriendListState(String owner) async {
    final friends = await readFriends(ownerUserId: owner);
    if (friends.isEmpty) return const FriendListCacheState();
    return FriendListCacheState(
      // Cached/search rows do not establish continuous server coverage, and
      // legacy timestamps may have lost fractions. Obtain an exact head first.
      hasMore: true,
      totalCount: friends.length,
      requiresCursorRepair: true,
    );
  }

  Future<void> _writeFriendListState({
    required String owner,
    required FriendPageCursor? cursor,
    required bool hasMore,
    required int totalCount,
    bool requiresCursorRepair = false,
  }) => _database
      .into(_database.cachedFriendListStates)
      .insertOnConflictUpdate(
        CachedFriendListStatesCompanion.insert(
          ownerUserId: owner,
          nextFriendsSince: Value(cursor?.friendsSince.toUtc()),
          nextFriendsSinceMicros: Value(
            cursor?.friendsSince.microsecondsSinceEpoch,
          ),
          nextFriendId: Value(cursor?.friendId),
          requiresCursorRepair: Value(requiresCursorRepair),
          hasMore: Value(hasMore),
          totalCount: Value(totalCount),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

  FriendListCacheState _mapFriendListState(CachedFriendListState row) {
    final micros = row.nextFriendsSinceMicros;
    final id = row.nextFriendId;
    return FriendListCacheState(
      nextCursor: micros == null || id == null
          ? null
          : FriendPageCursor(
              friendsSince: DateTime.fromMicrosecondsSinceEpoch(
                micros,
                isUtc: true,
              ),
              friendId: id,
            ),
      hasMore: row.hasMore,
      totalCount: row.totalCount,
      isAuthoritative: true,
      requiresCursorRepair:
          row.requiresCursorRepair || (row.hasMore && micros == null),
    );
  }

  Future<List<FriendRequest>> readRequests({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriendRequests)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.requestedAt)]);
    return (await query.get()).map(_mapRequest).toList(growable: false);
  }

  Future<FriendLocation?> readLocation(
    String friendId, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriendLocations)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.friendUserId.equals(friendId),
      );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return FriendLocation(
      latitude: row.latitude,
      longitude: row.longitude,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.locationUpdatedAtMs,
        isUtc: true,
      ),
    );
  }

  Future<void> writeLocation(
    String friendId,
    FriendLocation location, {
    String? ownerUserId,
  }) => _database
      .into(_database.cachedFriendLocations)
      .insertOnConflictUpdate(
        CachedFriendLocationsCompanion.insert(
          ownerUserId: ownerUserId ?? _userIdProvider(),
          friendUserId: friendId,
          latitude: location.latitude,
          longitude: location.longitude,
          locationUpdatedAtMs: location.updatedAt.millisecondsSinceEpoch,
          cachedAt: DateTime.now().toUtc(),
        ),
      );

  Future<bool> hasFreshLocation(
    String friendId, {
    required Duration maxAge,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriendLocations)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.friendUserId.equals(friendId),
      );
    final row = await query.getSingleOrNull();
    return row != null &&
        row.cachedAt.isAfter(DateTime.now().toUtc().subtract(maxAge));
  }

  Future<void> removeLocation(String friendId, {String? ownerUserId}) =>
      (_database.delete(_database.cachedFriendLocations)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()) &
                table.friendUserId.equals(friendId),
          ))
          .go();

  Future<UserDistance?> readDistance(
    String targetUserId, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedUserDistances)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.targetUserId.equals(targetUserId),
      );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return UserDistance(
      value: row.distanceValue,
      unit: DistanceUnit.values.byName(row.distanceUnit),
      updatedAt: row.locationUpdatedAt,
    );
  }

  Future<void> writeDistance(
    String targetUserId,
    UserDistance distance, {
    String? ownerUserId,
  }) => _database
      .into(_database.cachedUserDistances)
      .insertOnConflictUpdate(
        CachedUserDistancesCompanion.insert(
          ownerUserId: ownerUserId ?? _userIdProvider(),
          targetUserId: targetUserId,
          distanceValue: distance.value,
          distanceUnit: distance.unit.name,
          locationUpdatedAt: distance.updatedAt,
          cachedAt: DateTime.now().toUtc(),
        ),
      );

  Future<bool> hasFreshDistance(
    String targetUserId, {
    required Duration maxAge,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedUserDistances)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
            table.targetUserId.equals(targetUserId),
      );
    final row = await query.getSingleOrNull();
    return row != null &&
        row.cachedAt.isAfter(DateTime.now().toUtc().subtract(maxAge));
  }

  Future<void> removeDistance(String targetUserId, {String? ownerUserId}) =>
      (_database.delete(_database.cachedUserDistances)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()) &
                table.targetUserId.equals(targetUserId),
          ))
          .go();

  Future<void> clearDistances({String? ownerUserId}) =>
      (_database.delete(_database.cachedUserDistances)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()),
          ))
          .go();

  Future<bool> replaceAll({
    String? ownerUserId,
    required List<Friend> friends,
    required List<FriendRequest> requests,
    bool markFriendsComplete = false,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final cachedFriends = await readFriends(ownerUserId: owner);
    final cachedRequests = await readRequests(ownerUserId: owner);
    if (_sameFriends(cachedFriends, friends) &&
        _sameRequests(cachedRequests, requests)) {
      if (markFriendsComplete) {
        await _writeFriendListState(
          owner: owner,
          cursor: null,
          hasMore: false,
          totalCount: friends.length,
        );
      }
      return false;
    }

    await _database.transaction(() async {
      final cachedFriendsById = {
        for (final friend in cachedFriends) friend.id: friend,
      };
      final cachedRequestsById = {
        for (final request in cachedRequests) request.id: request,
      };
      final friendIds = friends.map((friend) => friend.id).toSet();
      final requestIds = requests.map((request) => request.id).toSet();

      await (_database.delete(_database.cachedFriends)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                (friendIds.isEmpty
                    ? const Constant(true)
                    : table.userId.isNotIn(friendIds)),
          ))
          .go();
      await (_database.delete(_database.cachedFriendRequests)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                (requestIds.isEmpty
                    ? const Constant(true)
                    : table.requestId.isNotIn(requestIds)),
          ))
          .go();

      for (final friend in friends) {
        if (_sameFriend(cachedFriendsById[friend.id], friend)) continue;
        await _database
            .into(_database.cachedFriends)
            .insertOnConflictUpdate(_friendRow(friend, owner));
      }
      for (final request in requests) {
        if (_sameRequest(cachedRequestsById[request.id], request)) continue;
        await _database
            .into(_database.cachedFriendRequests)
            .insertOnConflictUpdate(_requestRow(request, owner));
      }
      if (markFriendsComplete) {
        await _writeFriendListState(
          owner: owner,
          cursor: null,
          hasMore: false,
          totalCount: friends.length,
        );
      }
    });
    return true;
  }

  Future<bool> replaceRequests(
    List<FriendRequest> requests, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final cachedRequests = await readRequests(ownerUserId: owner);
    if (_sameRequests(cachedRequests, requests)) return false;
    await _database.transaction(() async {
      final cachedById = {
        for (final request in cachedRequests) request.id: request,
      };
      final requestIds = requests.map((request) => request.id).toSet();
      await (_database.delete(_database.cachedFriendRequests)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                (requestIds.isEmpty
                    ? const Constant(true)
                    : table.requestId.isNotIn(requestIds)),
          ))
          .go();
      for (final request in requests) {
        if (_sameRequest(cachedById[request.id], request)) continue;
        await _database
            .into(_database.cachedFriendRequests)
            .insertOnConflictUpdate(_requestRow(request, owner));
      }
    });
    return true;
  }

  bool _sameFriends(List<Friend> cached, List<Friend> incoming) {
    if (cached.length != incoming.length) return false;
    final cachedById = {for (final friend in cached) friend.id: friend};
    return incoming.every(
      (friend) => _sameFriend(cachedById[friend.id], friend),
    );
  }

  bool _sameRequests(List<FriendRequest> cached, List<FriendRequest> incoming) {
    if (cached.length != incoming.length) return false;
    final cachedById = {for (final request in cached) request.id: request};
    return incoming.every(
      (request) => _sameRequest(cachedById[request.id], request),
    );
  }

  bool _sameFriend(Friend? cached, Friend incoming) =>
      cached != null &&
      cached.id == incoming.id &&
      cached.username == incoming.username &&
      cached.displayName == incoming.displayName &&
      cached.avatarUrl == incoming.avatarUrl &&
      cached.avatarStoragePath == incoming.avatarStoragePath &&
      cached.friendsSince.isAtSameMomentAs(incoming.friendsSince);

  bool _sameRequest(FriendRequest? cached, FriendRequest incoming) =>
      cached != null &&
      cached.id == incoming.id &&
      cached.peerId == incoming.peerId &&
      cached.peerUsername == incoming.peerUsername &&
      cached.peerDisplayName == incoming.peerDisplayName &&
      cached.peerAvatarUrl == incoming.peerAvatarUrl &&
      cached.peerAvatarStoragePath == incoming.peerAvatarStoragePath &&
      cached.peerFriendCount == incoming.peerFriendCount &&
      cached.direction == incoming.direction &&
      _sameSecond(cached.requestedAt, incoming.requestedAt);

  bool _sameSecond(DateTime first, DateTime second) =>
      first.millisecondsSinceEpoch ~/ 1000 ==
      second.millisecondsSinceEpoch ~/ 1000;

  Future<void> addRequest(FriendRequest request, {String? ownerUserId}) =>
      _database
          .into(_database.cachedFriendRequests)
          .insertOnConflictUpdate(_requestRow(request, ownerUserId));

  Future<void> removeRequest(String requestId, {String? ownerUserId}) =>
      (_database.delete(_database.cachedFriendRequests)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()) &
                table.requestId.equals(requestId),
          ))
          .go();

  Future<void> acceptRequest(String requestId, {String? ownerUserId}) =>
      _database.transaction(() async {
        final owner = ownerUserId ?? _userIdProvider();
        final query = _database.select(_database.cachedFriendRequests)
          ..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.requestId.equals(requestId),
          );
        final row = await query.getSingleOrNull();
        if (row == null) return;
        final acceptedAt = DateTime.now();
        await (_database.delete(_database.cachedFriendRequests)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.requestId.equals(requestId),
            ))
            .go();
        await _database
            .into(_database.cachedFriends)
            .insertOnConflictUpdate(
              CachedFriendsCompanion.insert(
                ownerUserId: owner,
                userId: row.peerId,
                username: row.peerUsername,
                displayName: row.peerDisplayName,
                avatarUrl: Value(row.peerAvatarUrl),
                avatarStoragePath: Value(row.peerAvatarStoragePath),
                friendsSince: acceptedAt,
                friendsSinceMicros: Value(acceptedAt.microsecondsSinceEpoch),
                cachedAt: DateTime.now().toUtc(),
              ),
            );
      });

  Future<void> removeFriend(String friendId, {String? ownerUserId}) =>
      (_database.delete(_database.cachedFriends)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()) &
                table.userId.equals(friendId),
          ))
          .go();

  Future<void> _upsertFriends(List<Friend> friends, String owner) async {
    for (final friend in friends) {
      await _database
          .into(_database.cachedFriends)
          .insertOnConflictUpdate(_friendRow(friend, owner));
    }
  }

  Friend _mapFriend(CachedFriend row) => Friend(
    id: row.userId,
    username: row.username,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    avatarStoragePath: row.avatarStoragePath,
    cachedAvatarPath: _localAvatarPath(row),
    friendsSince: row.friendsSinceMicros == null
        ? row.friendsSince
        : DateTime.fromMicrosecondsSinceEpoch(
            row.friendsSinceMicros!,
            isUtc: true,
          ).toLocal(),
  );

  String? _localAvatarPath(CachedFriend row) {
    final storage = row.avatarStoragePath;
    final url = row.avatarUrl;
    if (storage?.isNotEmpty == true) {
      return _mediaCache?.localStorageFilePath(
        ownerUserId: row.ownerUserId,
        bucket: 'avatars',
        storagePath: storage!,
        mimeType: 'image/jpeg',
      );
    }
    return url?.isNotEmpty == true
        ? _mediaCache?.localStorageFilePath(
            ownerUserId: row.ownerUserId,
            bucket: MediaCacheService.externalAvatarsBucket,
            storagePath: url!,
          )
        : null;
  }

  FriendRequest _mapRequest(CachedFriendRequest row) => FriendRequest(
    id: row.requestId,
    peerId: row.peerId,
    peerUsername: row.peerUsername,
    peerDisplayName: row.peerDisplayName,
    peerAvatarUrl: row.peerAvatarUrl,
    peerAvatarStoragePath: row.peerAvatarStoragePath,
    peerFriendCount: row.peerFriendCount,
    direction: FriendRequestDirection.values.byName(row.direction),
    requestedAt: row.requestedAt,
  );

  CachedFriendsCompanion _friendRow(Friend friend, [String? ownerUserId]) =>
      CachedFriendsCompanion.insert(
        ownerUserId: ownerUserId ?? _userIdProvider(),
        userId: friend.id,
        username: friend.username,
        displayName: friend.displayName,
        avatarUrl: Value(friend.avatarUrl),
        avatarStoragePath: Value(friend.avatarStoragePath),
        friendsSince: friend.friendsSince,
        friendsSinceMicros: Value(friend.friendsSince.microsecondsSinceEpoch),
        cachedAt: DateTime.now().toUtc(),
      );

  CachedFriendRequestsCompanion _requestRow(
    FriendRequest request, [
    String? ownerUserId,
  ]) => CachedFriendRequestsCompanion.insert(
    ownerUserId: ownerUserId ?? _userIdProvider(),
    requestId: request.id,
    peerId: request.peerId,
    peerUsername: request.peerUsername,
    peerDisplayName: request.peerDisplayName,
    peerAvatarUrl: Value(request.peerAvatarUrl),
    peerAvatarStoragePath: Value(request.peerAvatarStoragePath),
    peerFriendCount: Value(request.peerFriendCount),
    direction: request.direction.name,
    requestedAt: request.requestedAt,
    cachedAt: DateTime.now().toUtc(),
  );
}

class FriendListCacheState {
  const FriendListCacheState({
    this.nextCursor,
    this.hasMore = false,
    this.totalCount = 0,
    this.isAuthoritative = false,
    this.requiresCursorRepair = false,
  });

  final FriendPageCursor? nextCursor;
  final bool hasMore;
  final int totalCount;

  /// False only for a best-effort state derived from a legacy cache that has
  /// no cursor metadata yet. A persisted page response is authoritative.
  final bool isAuthoritative;

  /// Retain offline rows while validating the legacy list from its exact head.
  /// Only a terminal server page completes this one-time repair.
  final bool requiresCursorRepair;
}
