import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  for (final metadata in ['terminal', 'partial', 'absent']) {
    test('upgrades v28 $metadata cache without losing offline rows', () async {
      final fixture = await _LegacyFixture.create(metadata: metadata);
      addTearDown(fixture.close);
      final cache = fixture.cache;
      expect((await cache.readFriends()).map((f) => f.id), [
        'f5',
        'f4',
        'f2',
        'f1',
      ]);
      expect((await cache.readRequests()).single.id, 'request');
      expect(
        (await fixture.database
                .customSelect('SELECT * FROM cached_messages')
                .get())
            .single
            .read<String>('message_text'),
        'untouched',
      );
      expect(
        (await cache.readFriends(
          ownerUserId: 'other',
        )).single.avatarStoragePath,
        'other/photo.jpg',
      );
      final state = await cache.readFriendListState();
      expect(state.hasMore, true);
      expect(state.requiresCursorRepair, true);
      expect(state.nextCursor, isNull);

      // An exact first page starts coverage, retaining the deeper offline rows.
      await cache.replaceFriendListHead(_page([6, 5]));
      expect((await cache.readFriends()).length, 5);
      expect((await cache.readFriendListState()).nextCursor!.friendId, 'f5');
      await cache.appendFriendPage(_page([4, 3]));
      expect((await cache.readFriends()).length, 6);
      final cursor = (await cache.readFriendListState()).nextCursor!;

      // A search or head sync cannot mistake an old, fully populated cache for
      // exact continuous coverage, or rewind an in-progress repair.
      await cache.cacheFoundFriends([_friend(2), _friend(1)]);
      await cache.replaceFriendListHead(_page([6, 5]));
      final during = await cache.readFriendListState();
      expect(during.requiresCursorRepair, true);
      expect(during.hasMore, true);
      expect(during.nextCursor!.friendId, cursor.friendId);
      expect(during.nextCursor!.friendsSince, cursor.friendsSince);

      await cache.appendFriendPage(_page([2, 1], hasMore: false));
      final complete = await cache.readFriendListState();
      expect(complete.requiresCursorRepair, false);
      expect(complete.hasMore, false);
      expect(complete.nextCursor, isNull);
      final friends = await cache.readFriends();
      expect(friends.map((f) => f.id), ['f6', 'f5', 'f4', 'f3', 'f2', 'f1']);
      for (final friend in friends) {
        expect(
          friend.friendsSince.toUtc(),
          _friend(int.parse(friend.id.substring(1))).friendsSince,
        );
      }
      await fixture.reopen();
      expect(
        (await fixture.cache.readFriendListState()).requiresCursorRepair,
        false,
      );
      expect((await fixture.cache.readFriends()).length, 6);
    });
  }

  test(
    'a complete first page ends repair when the server list shrank',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.close);
      await fixture.cache.replaceFriendListHead(_page([6, 5]));
      await fixture.cache.replaceFriendListHead(
        FriendPage(friends: [_friend(6)], hasMore: false, totalCount: 1),
      );
      expect((await fixture.cache.readFriends()).single.id, 'f6');
      final state = await fixture.cache.readFriendListState();
      expect(state.hasMore, false);
      expect(state.requiresCursorRepair, false);
      expect(state.nextCursor, isNull);
    },
  );

  test(
    'empty legacy owner stays complete and separate from populated owners',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.close);
      final empty = await fixture.cache.readFriendListState(
        ownerUserId: 'empty',
      );
      expect(empty.hasMore, false);
      expect(empty.requiresCursorRepair, false);
      expect(await fixture.cache.readFriends(ownerUserId: 'empty'), isEmpty);
      expect(
        (await fixture.cache.readFriendListState()).requiresCursorRepair,
        true,
      );
    },
  );

  test(
    'v28 upgrade tolerates precision columns already physically present',
    () async {
      final fixture = await _LegacyFixture.create(keepPrecisionColumns: true);
      addTearDown(fixture.close);
      expect(
        (await fixture.cache.readFriendListState()).requiresCursorRepair,
        true,
      );
      expect((await fixture.cache.readFriends()).length, 4);
    },
  );
}

Friend _friend(int n) => Friend(
  id: 'f$n',
  username: 'f$n',
  displayName: 'Friend $n',
  friendsSince: DateTime.utc(2026, 10, 28, 20, 22, n, 881, 612),
);
FriendPage _page(List<int> numbers, {bool hasMore = true}) => FriendPage(
  friends: numbers.map(_friend).toList(),
  hasMore: hasMore,
  totalCount: 6,
);

class _LegacyFixture {
  _LegacyFixture(this.connection, this.database);
  final sqlite.Database connection;
  AppDatabase database;
  FriendsCacheDataSource get cache =>
      FriendsCacheDataSource(database: database, userIdProvider: () => 'owner');

  static Future<_LegacyFixture> create({
    String metadata = 'terminal',
    bool keepPrecisionColumns = false,
  }) async {
    final connection = sqlite.sqlite3.openInMemory();
    final fixture = _LegacyFixture(
      connection,
      AppDatabase.forTesting(
        NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
      ),
    );
    await fixture.cache.replaceAll(
      friends: [5, 4, 2, 1].map(_friend).toList(),
      requests: [
        FriendRequest(
          id: 'request',
          peerId: 'request-peer',
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
          direction: FriendRequestDirection.incoming,
          requestedAt: DateTime.utc(2026),
        ),
      ],
      markFriendsComplete: true,
    );
    await fixture.cache.replaceAll(
      ownerUserId: 'other',
      friends: [
        Friend(
          id: 'other-peer',
          username: 'other',
          displayName: 'Other',
          avatarStoragePath: 'other/photo.jpg',
          friendsSince: DateTime.utc(2026),
        ),
      ],
      requests: const [],
      markFriendsComplete: true,
    );
    await fixture.cache.replaceAll(
      ownerUserId: 'empty',
      friends: const [],
      requests: const [],
      markFriendsComplete: true,
    );
    await ChatCacheDataSource(
      database: fixture.database,
      userIdProvider: () => 'owner',
    ).upsertMessages([
      ChatMessage(
        id: 'message',
        chatId: 'chat',
        senderId: 'peer',
        text: 'untouched',
        timestamp: DateTime.utc(2026),
        isMine: false,
      ),
    ]);
    if (metadata == 'absent') {
      await fixture.database.customStatement(
        "DELETE FROM cached_friend_list_states WHERE owner_user_id='owner'",
      );
    } else {
      await fixture.database.customStatement(
        '''
        UPDATE cached_friend_list_states SET total_count=6,has_more=?,next_friends_since=1,next_friend_id='f1'
        WHERE owner_user_id='owner'
      ''',
        [metadata == 'partial' ? 1 : 0],
      );
    }
    if (!keepPrecisionColumns) {
      await fixture.database.customStatement(
        'ALTER TABLE cached_friends DROP COLUMN friends_since_micros',
      );
      await fixture.database.customStatement(
        'ALTER TABLE cached_friend_list_states DROP COLUMN next_friends_since_micros',
      );
      await fixture.database.customStatement(
        'ALTER TABLE cached_friend_list_states DROP COLUMN requires_cursor_repair',
      );
    }
    await fixture.database.customStatement('PRAGMA user_version=28');
    await fixture.reopen();
    return fixture;
  }

  Future<void> reopen() async {
    await database.close();
    database = AppDatabase.forTesting(
      NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
    );
  }

  Future<void> close() async {
    await database.close();
    connection.close();
  }
}
