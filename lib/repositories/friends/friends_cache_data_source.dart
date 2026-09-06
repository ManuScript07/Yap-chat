import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/friends/data/data.dart';

class FriendsCacheDataSource {
  const FriendsCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
  }) : _database = database,
       _userIdProvider = userIdProvider;

  final AppDatabase _database;
  final String Function() _userIdProvider;

  Stream<List<Friend>> watchFriends({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedFriends)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.friendsSince)]);
    return query.watch().map((rows) => List.unmodifiable(rows.map(_mapFriend)));
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
      ..orderBy([(table) => OrderingTerm.desc(table.friendsSince)]);
    return (await query.get()).map(_mapFriend).toList(growable: false);
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
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final cachedFriends = await readFriends(ownerUserId: owner);
    final cachedRequests = await readRequests(ownerUserId: owner);
    if (_sameFriends(cachedFriends, friends) &&
        _sameRequests(cachedRequests, requests)) {
      await _removeExpiredLocations(owner);
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
      await _removeExpiredLocations(owner);
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
      _sameSecond(cached.friendsSince, incoming.friendsSince);

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

  Future<void> _removeExpiredLocations(String owner) async {
    final cachedLocations = await (_database.select(
      _database.cachedFriendLocations,
    )..where((table) => table.ownerUserId.equals(owner))).get();
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final expiredLocationIds = cachedLocations
        .where(
          (row) => DateTime.fromMillisecondsSinceEpoch(
            row.locationUpdatedAtMs,
            isUtc: true,
          ).isBefore(cutoff),
        )
        .map((row) => row.friendUserId)
        .toList(growable: false);
    const deleteBatchSize = 500;
    for (
      var offset = 0;
      offset < expiredLocationIds.length;
      offset += deleteBatchSize
    ) {
      final end = (offset + deleteBatchSize).clamp(
        0,
        expiredLocationIds.length,
      );
      await (_database.delete(_database.cachedFriendLocations)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.friendUserId.isIn(
                  expiredLocationIds.sublist(offset, end),
                ),
          ))
          .go();
    }
  }

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
                friendsSince: DateTime.now(),
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

  Friend _mapFriend(CachedFriend row) => Friend(
    id: row.userId,
    username: row.username,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    avatarStoragePath: row.avatarStoragePath,
    friendsSince: row.friendsSince,
  );

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
