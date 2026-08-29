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

  Future<void> removeLocation(String friendId, {String? ownerUserId}) =>
      (_database.delete(_database.cachedFriendLocations)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId ?? _userIdProvider()) &
                table.friendUserId.equals(friendId),
          ))
          .go();

  Future<void> replaceAll({
    String? ownerUserId,
    required List<Friend> friends,
    required List<FriendRequest> requests,
  }) => _database.transaction(() async {
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.delete(
      _database.cachedFriends,
    )..where((table) => table.ownerUserId.equals(owner))).go();
    await (_database.delete(
      _database.cachedFriendRequests,
    )..where((table) => table.ownerUserId.equals(owner))).go();
    for (final friend in friends) {
      await _database
          .into(_database.cachedFriends)
          .insert(_friendRow(friend, owner));
    }
    for (final request in requests) {
      await _database
          .into(_database.cachedFriendRequests)
          .insert(_requestRow(request, owner));
    }
    final friendIds = friends.map((friend) => friend.id).toSet();
    final cachedLocations = await (_database.select(
      _database.cachedFriendLocations,
    )..where((table) => table.ownerUserId.equals(owner))).get();
    final obsoleteLocationIds = cachedLocations
        .map((row) => row.friendUserId)
        .where((friendId) => !friendIds.contains(friendId))
        .toList(growable: false);
    const deleteBatchSize = 500;
    for (
      var offset = 0;
      offset < obsoleteLocationIds.length;
      offset += deleteBatchSize
    ) {
      final end = (offset + deleteBatchSize).clamp(
        0,
        obsoleteLocationIds.length,
      );
      await (_database.delete(_database.cachedFriendLocations)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.friendUserId.isIn(
                  obsoleteLocationIds.sublist(offset, end),
                ),
          ))
          .go();
    }
  });

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
