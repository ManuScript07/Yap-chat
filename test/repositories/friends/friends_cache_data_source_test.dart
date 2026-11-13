import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  test('isolates friend cache between authenticated users', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var owner = 'owner-1';
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    );

    await cache.replaceAll(friends: [_friend('friend-1')], requests: const []);
    owner = 'owner-2';
    await cache.replaceAll(friends: [_friend('friend-2')], requests: const []);

    expect((await cache.readFriends()).single.id, 'friend-2');
    owner = 'owner-1';
    expect((await cache.readFriends()).single.id, 'friend-1');
  });

  test('skips identical friend and request snapshots', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const owner = 'owner';
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    );
    final friend = _friend('friend');

    expect(
      await cache.replaceAll(friends: [friend], requests: const []),
      isTrue,
    );
    expect(
      await cache.replaceAll(friends: [friend], requests: const []),
      isFalse,
    );
  });

  test('optimistically converts an incoming request to a friend', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    await cache.replaceAll(
      friends: const [],
      requests: [_request('request-1')],
    );

    await cache.acceptRequest('request-1');

    expect(await cache.readRequests(), isEmpty);
    final friend = (await cache.readFriends()).single;
    expect(friend.id, 'peer-request-1');
    expect(friend.username, 'username');
  });

  test('stores friend locations per authenticated user', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var owner = 'owner-1';
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    );
    final location = FriendLocation(
      latitude: 55.75,
      longitude: 37.61,
      updatedAt: DateTime.utc(2026, 8, 25, 10),
    );

    await cache.writeLocation('friend-1', location);
    expect(await cache.readLocation('friend-1'), location);
    owner = 'owner-2';
    expect(await cache.readLocation('friend-1'), isNull);
  });

  test('keeps a recent cached location after friendship ends', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    await cache.writeLocation(
      'removed-friend',
      FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
    );

    await cache.replaceAll(
      friends: [_friend('active-friend')],
      requests: const [],
    );

    expect(await cache.readLocation('removed-friend'), isNotNull);
  });

  test('retains a cached location older than 24 hours', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    await cache.writeLocation(
      'expired-friend',
      FriendLocation(
        latitude: 55.75,
        longitude: 37.61,
        updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
      ),
    );

    await cache.replaceAll(friends: const [], requests: const []);

    expect(await cache.readLocation('expired-friend'), isNotNull);
  });

  test('persists cursor state and appends a subsequent friend page', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    final newest = _friend('friend-3', day: 3);
    final middle = _friend('friend-2', day: 2);
    final oldest = _friend('friend-1', day: 1);

    await cache.replaceFriendListHead(
      FriendPage(friends: [newest, middle], hasMore: true, totalCount: 3),
    );
    final firstState = await cache.readFriendListState();
    expect(firstState.isAuthoritative, isTrue);
    expect(firstState.hasMore, isTrue);
    expect(firstState.totalCount, 3);
    expect(firstState.nextCursor?.friendId, middle.id);

    await cache.appendFriendPage(
      FriendPage(friends: [oldest], hasMore: false, totalCount: 3),
    );

    expect((await cache.readFriends()).map((friend) => friend.id), [
      newest.id,
      middle.id,
      oldest.id,
    ]);
    final finalState = await cache.readFriendListState();
    expect(finalState.isAuthoritative, isTrue);
    expect(finalState.hasMore, isFalse);
    expect(finalState.totalCount, 3);
  });

  test('head refresh keeps already cached deeper pages and cursor', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    final newest = _friend('friend-4', day: 4);
    final pageOneLast = _friend('friend-3', day: 3);
    final pageTwoFirst = _friend('friend-2', day: 2);
    final oldest = _friend('friend-1', day: 1);
    await cache.replaceFriendListHead(
      FriendPage(
        friends: [pageOneLast, pageTwoFirst],
        hasMore: true,
        totalCount: 3,
      ),
    );
    await cache.appendFriendPage(
      FriendPage(friends: [oldest], hasMore: false, totalCount: 3),
    );

    await cache.replaceFriendListHead(
      FriendPage(friends: [newest, pageOneLast], hasMore: true, totalCount: 4),
    );

    expect((await cache.readFriends()).map((friend) => friend.id), [
      newest.id,
      pageOneLast.id,
      pageTwoFirst.id,
      oldest.id,
    ]);
    final state = await cache.readFriendListState();
    expect(state.hasMore, isFalse);
    expect(state.nextCursor, isNull);
    expect(state.totalCount, 4);
  });

  test(
    'head refresh removes a stale optimistic friend but keeps deeper pages',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = FriendsCacheDataSource(
        database: database,
        userIdProvider: () => 'owner',
      );
      final currentHead = _friend('friend-3', day: 3);
      final headBoundary = _friend('friend-2', day: 2);
      final deeperFriend = _friend('friend-1', day: 1);
      final optimisticFriend = _friend('optimistic', day: 4);
      await cache.replaceFriendListHead(
        FriendPage(
          friends: [currentHead, headBoundary],
          hasMore: true,
          totalCount: 3,
        ),
      );
      await cache.appendFriendPage(
        FriendPage(friends: [deeperFriend], hasMore: false, totalCount: 3),
      );
      await cache.updateFriendFromRealtime(
        optimisticFriend,
        friendId: optimisticFriend.id,
      );

      await cache.replaceFriendListHead(
        FriendPage(
          friends: [currentHead, headBoundary],
          hasMore: true,
          totalCount: 3,
        ),
      );

      expect((await cache.readFriends()).map((friend) => friend.id), [
        currentHead.id,
        headBoundary.id,
        deeperFriend.id,
      ]);
    },
  );

  test('an empty successful head removes all stale local friends', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    await cache.replaceAll(
      friends: [_friend('optimistic')],
      requests: const [],
    );

    await cache.replaceFriendListHead(
      const FriendPage(friends: [], hasMore: false, totalCount: 0),
    );

    expect(await cache.readFriends(), isEmpty);
  });

  test('marks a legacy complete snapshot as a terminal page', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );

    await cache.replaceAll(
      friends: [_friend('friend-2', day: 2), _friend('friend-1', day: 1)],
      requests: const [],
      markFriendsComplete: true,
    );

    final state = await cache.readFriendListState();
    expect(state.totalCount, 2);
    expect(state.hasMore, isFalse);
    expect(state.nextCursor, isNull);
  });

  test(
    'keeps cursor pagination intact when search finds a later friend',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = FriendsCacheDataSource(
        database: database,
        userIdProvider: () => 'owner',
      );
      final newest = _friend('friend-3', day: 3);
      final pageCursor = _friend('friend-2', day: 2);
      final searchedLaterFriend = _friend('friend-1', day: 1);
      await cache.replaceFriendListHead(
        FriendPage(friends: [newest, pageCursor], hasMore: true, totalCount: 3),
      );

      await cache.cacheFoundFriends([searchedLaterFriend]);

      expect((await cache.readFriends()).map((friend) => friend.id), [
        newest.id,
        pageCursor.id,
        searchedLaterFriend.id,
      ]);
      final state = await cache.readFriendListState();
      expect(state.nextCursor, isNull);
      expect(state.hasMore, isFalse);
      expect(state.totalCount, 3);
    },
  );
}

Friend _friend(String id, {int day = 24}) => Friend(
  id: id,
  username: 'username',
  displayName: 'Name',
  friendsSince: DateTime.utc(2026, 8, day),
);

FriendRequest _request(String id) => FriendRequest(
  id: id,
  peerId: 'peer-$id',
  peerUsername: 'username',
  peerDisplayName: 'Name',
  peerFriendCount: 3,
  direction: FriendRequestDirection.incoming,
  requestedAt: DateTime.utc(2026, 8, 24),
);
