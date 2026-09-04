import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';

class ViewedProfileCacheDataSource {
  const ViewedProfileCacheDataSource({
    required AppDatabase database,
    required ProfileCacheDataSource profileCache,
  }) : _database = database,
       _profileCache = profileCache;

  final AppDatabase _database;
  final ProfileCacheDataSource _profileCache;

  Future<ViewedProfile?> read(String ownerUserId, String targetUserId) async {
    final profile = await _profileCache.read(targetUserId);
    if (profile == null) return null;
    final query = _database.select(_database.cachedViewedProfileMetadata)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.targetUserId.equals(targetUserId),
      );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ViewedProfile(
      profile: profile,
      relationship: ProfileRelationship.values.byName(row.relationship),
      requestId: row.requestId,
      friendCount: row.friendCount,
      friendsPreview: _decodeFriends(row.friendsPreviewJson),
      viewCount: row.viewCount,
      lastSeenAt: row.lastSeenAt,
      showsLastSeen: row.showsLastSeen,
    );
  }

  Future<void> write(String ownerUserId, ViewedProfile viewedProfile) async {
    await _profileCache.write(viewedProfile.profile);
    await _database
        .into(_database.cachedViewedProfileMetadata)
        .insertOnConflictUpdate(
          CachedViewedProfileMetadataCompanion.insert(
            ownerUserId: ownerUserId,
            targetUserId: viewedProfile.profile.id,
            relationship: viewedProfile.relationship.name,
            requestId: Value(viewedProfile.requestId),
            friendCount: viewedProfile.friendCount,
            friendsPreviewJson: jsonEncode(
              viewedProfile.friendsPreview.map(_friendToMap).toList(),
            ),
            viewCount: viewedProfile.viewCount,
            lastSeenAt: Value(viewedProfile.lastSeenAt),
            showsLastSeen: viewedProfile.showsLastSeen,
            cachedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<List<ViewedProfileFriend>> readFriends(
    String ownerUserId,
    String targetUserId,
  ) async {
    final query = _database.select(_database.cachedViewedProfileFriends)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.targetUserId.equals(targetUserId),
      )
      ..orderBy([
        (table) => OrderingTerm.asc(table.displayName),
        (table) => OrderingTerm.asc(table.friendUserId),
      ]);
    return (await query.get())
        .map(
          (row) => ViewedProfileFriend(
            id: row.friendUserId,
            username: row.username,
            displayName: row.displayName,
            avatarUrl: row.avatarUrl,
            avatarStoragePath: row.avatarStoragePath,
            mutualFriendCount: row.mutualFriendCount,
          ),
        )
        .toList(growable: false);
  }

  Future<DateTime?> readFriendsCachedAt(
    String ownerUserId,
    String targetUserId,
  ) async {
    final query = _database.select(_database.cachedViewedProfileFriendLists)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.targetUserId.equals(targetUserId),
      );
    return (await query.getSingleOrNull())?.cachedAt;
  }

  Future<ViewedProfileFriendsSnapshot?> readFriendsSnapshot(
    String ownerUserId,
    String targetUserId,
  ) async {
    final markerQuery = _database.select(_database.cachedViewedProfileFriendLists)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.targetUserId.equals(targetUserId),
      );
    final marker = await markerQuery.getSingleOrNull();
    if (marker == null) return null;
    return ViewedProfileFriendsSnapshot(
      friends: await readFriends(ownerUserId, targetUserId),
      hasMore: marker.hasMore,
      cachedAt: marker.cachedAt,
    );
  }

  Future<void> replaceFriends(
    String ownerUserId,
    String targetUserId,
    List<ViewedProfileFriend> friends, {
    bool hasMore = false,
  }
  ) => _database.transaction(() async {
    final cachedAt = DateTime.now().toUtc();
    await (_database.delete(_database.cachedViewedProfileFriends)..where(
          (table) =>
              table.ownerUserId.equals(ownerUserId) &
              table.targetUserId.equals(targetUserId),
        ))
        .go();
    for (final friend in friends) {
      await _database
          .into(_database.cachedViewedProfileFriends)
          .insert(
            CachedViewedProfileFriendsCompanion.insert(
              ownerUserId: ownerUserId,
              targetUserId: targetUserId,
              friendUserId: friend.id,
              username: friend.username,
              displayName: friend.displayName,
              avatarUrl: Value(friend.avatarUrl),
              avatarStoragePath: Value(friend.avatarStoragePath),
              mutualFriendCount: Value(friend.mutualFriendCount),
              cachedAt: cachedAt,
            ),
          );
    }
    await _database
        .into(_database.cachedViewedProfileFriendLists)
        .insertOnConflictUpdate(
          CachedViewedProfileFriendListsCompanion.insert(
            ownerUserId: ownerUserId,
            targetUserId: targetUserId,
            hasMore: Value(hasMore),
            cachedAt: cachedAt,
          ),
        );
  });

  Future<void> appendFriends(
    String ownerUserId,
    String targetUserId,
    List<ViewedProfileFriend> friends, {
    required bool hasMore,
  }) => _database.transaction(() async {
    final cachedAt = DateTime.now().toUtc();
    for (final friend in friends) {
      await _database
          .into(_database.cachedViewedProfileFriends)
          .insertOnConflictUpdate(
            CachedViewedProfileFriendsCompanion.insert(
              ownerUserId: ownerUserId,
              targetUserId: targetUserId,
              friendUserId: friend.id,
              username: friend.username,
              displayName: friend.displayName,
              avatarUrl: Value(friend.avatarUrl),
              avatarStoragePath: Value(friend.avatarStoragePath),
              mutualFriendCount: Value(friend.mutualFriendCount),
              cachedAt: cachedAt,
            ),
          );
    }
    await _database
        .into(_database.cachedViewedProfileFriendLists)
        .insertOnConflictUpdate(
          CachedViewedProfileFriendListsCompanion.insert(
            ownerUserId: ownerUserId,
            targetUserId: targetUserId,
            hasMore: Value(hasMore),
            cachedAt: cachedAt,
          ),
        );
  });

  Future<int?> readViewCount(String ownerUserId, String targetUserId) async {
    final query = _database.select(_database.cachedProfileViewCounts)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.targetUserId.equals(targetUserId),
      );
    return (await query.getSingleOrNull())?.viewCount;
  }

  Future<void> writeViewCount(
    String ownerUserId,
    String targetUserId,
    int viewCount,
  ) => _database
      .into(_database.cachedProfileViewCounts)
      .insertOnConflictUpdate(
        CachedProfileViewCountsCompanion.insert(
          ownerUserId: ownerUserId,
          targetUserId: targetUserId,
          viewCount: viewCount,
          cachedAt: DateTime.now().toUtc(),
        ),
      );

  Map<String, Object?> _friendToMap(ViewedProfileFriend friend) => {
    'id': friend.id,
    'username': friend.username,
    'display_name': friend.displayName,
    'avatar_url': friend.avatarUrl,
    'avatar_storage_path': friend.avatarStoragePath,
    'mutual_friend_count': friend.mutualFriendCount,
  };

  List<ViewedProfileFriend> _decodeFriends(String value) {
    try {
      return (jsonDecode(value) as List<dynamic>)
          .map((item) => _friendFromMap(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  ViewedProfileFriend _friendFromMap(Map<String, dynamic> row) =>
      ViewedProfileFriend(
        id: row['id'] as String,
        username: row['username'] as String? ?? '',
        displayName: row['display_name'] as String? ?? '',
        avatarUrl: row['avatar_storage_path'] == null
            ? row['avatar_url'] as String?
            : null,
        avatarStoragePath: row['avatar_storage_path'] as String?,
        mutualFriendCount: (row['mutual_friend_count'] as num?)?.toInt() ?? 0,
      );
}
