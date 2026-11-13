import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  late AppDatabase database;
  late FriendsCacheDataSource cache;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cache = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
  });
  tearDown(() => database.close());

  test('preserves exact UTC and offset cursor timestamps', () async {
    for (final timestamp in [
      '2026-10-28T20:22:16.881612Z',
      '2026-10-28T23:22:16.881612+03:00',
      '2026-10-28T20:22:16.000001Z',
      '2026-10-28T20:22:16Z',
    ]) {
      final friend = _friend('peer', timestamp);
      await cache.replaceFriendListHead(
        FriendPage(friends: [friend], hasMore: true, totalCount: 2),
      );
      final state = await cache.readFriendListState();
      expect(
        state.nextCursor!.friendsSince.toUtc(),
        friend.friendsSince.toUtc(),
      );
      expect(
        (await cache.readFriends()).single.friendsSince.toUtc(),
        friend.friendsSince.toUtc(),
      );
    }
  });

  test(
    'orders friendships by microseconds before the id tie breaker',
    () async {
      final newer = _friend('a', '2026-10-28T20:22:16.900001Z');
      final sameTimeHighId = _friend('z', '2026-10-28T20:22:16.800001Z');
      final sameTimeLowId = _friend('b', '2026-10-28T20:22:16.800001Z');
      await cache.replaceAll(
        friends: [sameTimeLowId, newer, sameTimeHighId],
        requests: const [],
      );
      expect((await cache.readFriends()).map((f) => f.id), ['a', 'z', 'b']);
      expect((await cache.watchFriends().first).map((f) => f.id), [
        'a',
        'z',
        'b',
      ]);
    },
  );

  test('same-second authoritative head removes an absent friend', () async {
    final removed = _friend('removed', '2026-10-28T20:22:16.900001Z');
    final boundary = _friend('boundary', '2026-10-28T20:22:16.800001Z');
    final deeper = _friend('deeper', '2026-10-28T20:22:16.700001Z');
    await cache.replaceAll(
      friends: [removed, boundary, deeper],
      requests: const [],
    );
    await cache.replaceFriendListHead(
      FriendPage(friends: [boundary], hasMore: true, totalCount: 2),
    );
    expect((await cache.readFriends()).map((f) => f.id), [
      'boundary',
      'deeper',
    ]);
  });

  test(
    'a changed subsecond friendship is not discarded as identical',
    () async {
      final before = _friend('peer', '2026-10-28T20:22:16.100001Z');
      final after = _friend('peer', '2026-10-28T20:22:16.900001Z');
      await cache.replaceAll(friends: [before], requests: const []);
      expect(
        await cache.replaceAll(friends: [after], requests: const []),
        true,
      );
      expect(
        (await cache.readFriends()).single.friendsSince.toUtc(),
        after.friendsSince,
      );
    },
  );
  for (final scenario in [(160, 4), (160, 160), (1001, 1)]) {
    test(
      'loads all ${scenario.$1} friends with timestamp groups ${scenario.$2}',
      () async {
        final base = DateTime.utc(2026, 10, 28, 20, 22, 16);
        final ordered = [
          for (var i = 0; i < scenario.$1; i++)
            Friend(
              id: 'peer-${(scenario.$1 - i).toString().padLeft(5, '0')}',
              username: 'peer$i',
              displayName: 'Friend $i',
              friendsSince: base.subtract(
                Duration(microseconds: (i ~/ scenario.$2) * 13 + 1),
              ),
            ),
        ];
        FriendPage fetch(FriendPageCursor? cursor) {
          final remaining = ordered
              .where(
                (friend) =>
                    cursor == null ||
                    friend.friendsSince.isBefore(cursor.friendsSince) ||
                    (friend.friendsSince.isAtSameMomentAs(
                          cursor.friendsSince,
                        ) &&
                        friend.id.compareTo(cursor.friendId) < 0),
              )
              .toList();
          return FriendPage(
            friends: remaining.take(50).toList(),
            hasMore: remaining.length > 50,
            totalCount: ordered.length,
          );
        }

        await cache.replaceFriendListHead(fetch(null));
        var calls = 1;
        while ((await cache.readFriendListState()).hasMore) {
          final cursor = (await cache.readFriendListState()).nextCursor;
          expect(cursor, isNotNull);
          await cache.appendFriendPage(fetch(cursor));
          expect(++calls, lessThan(30));
        }
        expect(
          (await cache.readFriends()).map((f) => f.id),
          ordered.map((f) => f.id),
        );
        expect(calls, (scenario.$1 / 50).ceil());
      },
    );
  }
}

Friend _friend(String id, String timestamp) => Friend(
  id: id,
  username: id,
  displayName: id,
  friendsSince: DateTime.parse(timestamp),
);
