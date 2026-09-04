import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';
import 'package:yap_chat/repositories/profile/viewed_profile_cache_data_source.dart';

void main() {
  test('keeps viewer-specific metadata scoped to its owner account', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final profileCache = ProfileCacheDataSource(database: database);
    final cache = ViewedProfileCacheDataSource(
      database: database,
      profileCache: profileCache,
    );
    final profile = UserProfile(
      id: 'target',
      username: 'target_user',
      displayName: 'Target',
      onboardingCompleted: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await cache.write(
      'owner-one',
      ViewedProfile(
        profile: profile,
        relationship: ProfileRelationship.friend,
        friendCount: 12,
        friendsPreview: const [
          ViewedProfileFriend(
            id: 'friend',
            username: 'friend_user',
            displayName: 'Friend',
          ),
        ],
        viewCount: 7,
        showsLastSeen: true,
      ),
    );

    expect(await cache.read('owner-two', 'target'), isNull);
    final restored = await cache.read('owner-one', 'target');
    expect(restored?.relationship, ProfileRelationship.friend);
    expect(restored?.friendCount, 12);
    expect(restored?.friendsPreview.single.id, 'friend');
    expect(restored?.viewCount, 7);
  });

  test('replaces a viewed users cached friend list atomically', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ViewedProfileCacheDataSource(
      database: database,
      profileCache: ProfileCacheDataSource(database: database),
    );
    const first = ViewedProfileFriend(
      id: 'first',
      username: 'first_user',
      displayName: 'First',
    );
    const second = ViewedProfileFriend(
      id: 'second',
      username: 'second_user',
      displayName: 'Second',
    );

    await cache.replaceFriends('owner', 'target', const [first]);
    final firstCachedAt = await cache.readFriendsCachedAt('owner', 'target');
    await cache.replaceFriends('owner', 'target', const [second]);

    expect(await cache.readFriends('owner', 'target'), const [second]);
    expect(firstCachedAt, isNotNull);
    expect(await cache.readFriendsCachedAt('owner', 'target'), isNotNull);
  });

  test('records a successful empty friend-list response', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ViewedProfileCacheDataSource(
      database: database,
      profileCache: ProfileCacheDataSource(database: database),
    );

    await cache.replaceFriends('owner', 'target', const []);

    expect(await cache.readFriends('owner', 'target'), isEmpty);
    expect(await cache.readFriendsCachedAt('owner', 'target'), isNotNull);
  });

  test('appends a paginated page and persists its cursor state', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ViewedProfileCacheDataSource(
      database: database,
      profileCache: ProfileCacheDataSource(database: database),
    );
    const alice = ViewedProfileFriend(
      id: 'alice',
      username: 'alice_user',
      displayName: 'Alice',
      mutualFriendCount: 2,
    );
    const bob = ViewedProfileFriend(
      id: 'bob',
      username: 'bob_user',
      displayName: 'Bob',
    );

    await cache.replaceFriends('owner', 'target', const [alice], hasMore: true);
    await cache.appendFriends('owner', 'target', const [bob], hasMore: false);

    final snapshot = await cache.readFriendsSnapshot('owner', 'target');
    expect(snapshot?.friends, const [alice, bob]);
    expect(snapshot?.hasMore, isFalse);
    expect(snapshot?.cachedAt, isNotNull);
  });
}
