import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

final _epoch = DateTime.utc(2026, 10, 27);
String _id(int n) => 'chat-${n.toString().padLeft(5, '0')}';
DateTime _at(int micros) => _epoch.add(Duration(microseconds: micros));

Chat _chat(int n, {String? name, DateTime? time}) => Chat(
  id: _id(n),
  peerId: 'peer-$n',
  peerUsername: 'username_$n',
  userName: name ?? 'АЛЕКСЕЙ $n',
  avatarStoragePath: 'peer-$n/avatar.jpg',
  lastMessageId: 'message-$n',
  lastMessage: 'preview $n',
  // Include ties and subsecond differences that Drift's DateTime cannot store.
  lastMessageTime: time ?? _at(n ~/ 3),
  unreadCount: n % 7,
  isOnline: false,
  lastSeenAt: _epoch.subtract(const Duration(minutes: 1)),
  isLastMessageFromMe: n.isEven,
  isMuted: n.isOdd,
);

Future<void> _coverHead(ChatsCacheDataSource cache) async {
  final items = [
    for (var n = 2004; n >= 1955; n--)
      ChatListPageItem(chat: _chat(n), activityAt: _at(n ~/ 3)),
  ];
  expect(
    await cache.applyListPage(
      await cache.beginListRefresh(),
      ChatListPage(
        items: items,
        query: '',
        nextCursor: ChatListPageCursor(
          activityAt: items.last.activityAt,
          conversationId: items.last.chat.id,
        ),
        unreadTotal: 37,
      ),
    ),
    isTrue,
  );
}

Future<T> _next<T>(StreamIterator<T> iterator) async {
  expect(
    await iterator.moveNext().timeout(const Duration(seconds: 5)),
    isTrue,
    reason: 'The production cache stream unexpectedly closed',
  );
  return iterator.current;
}

void main() {
  group('available local chat cache', () {
    late AppDatabase db;
    late ChatsCacheDataSource cache;
    late _SelectTrace trace;
    late _Media media;
    var owner = 'owner';

    setUp(() {
      owner = 'owner';
      trace = _SelectTrace();
      db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(trace));
      addTearDown(db.close);
      media = _Media(db);
      cache = ChatsCacheDataSource(
        database: db,
        userIdProvider: () => owner,
        mediaCache: media,
      );
    });

    test(
      '2005 retained chats remain pageable with only 50 covered remotely',
      () async {
        await cache.replaceAll([for (var n = 0; n < 2005; n++) _chat(n)]);
        await cache.replaceAll([_chat(2005)], ownerUserId: 'other');
        // Capture a local continuation before remote coverage exists.
        final initial = await cache.readAvailableSlice();
        await _coverHead(cache);
        expect((await cache.readListSlice()).chats, hasLength(50));
        expect(await db.select(db.cachedChatListEntries).get(), hasLength(50));
        final state = await cache.readListState();
        final badge = await cache.readUnreadState();

        trace.clear();
        media.paths = 0;
        final seen = <String>[...initial.chats.map((c) => c.id)];
        var cursor = initial.nextCursor;
        var pages = 1;
        while (cursor != null) {
          final slice = await cache.readAvailableSlice(after: cursor);
          expect(slice.serverBacked, isFalse);
          expect(slice.chats.length, lessThanOrEqualTo(50));
          expect(
            slice.orderByChatId.keys,
            unorderedEquals(slice.chats.map((c) => c.id)),
          );
          seen.addAll(slice.chats.map((c) => c.id));
          cursor = slice.nextCursor;
          if (cursor != null) {
            expect(cursor.serverBacked, isFalse);
            expect(cursor.activityMicros, slice.orderByChatId[cursor.chatId]);
          }
          expect(
            ++pages,
            lessThanOrEqualTo(41),
            reason: 'Cursor did not advance',
          );
        }
        expect(seen, [for (var n = 2004; n >= 0; n--) _id(n)]);
        expect(seen.toSet(), hasLength(2005));
        expect(pages, 41);
        expect(
          media.paths,
          1955,
          reason: 'Only returned rows need avatar mapping',
        );
        expect(trace.slices, hasLength(40));
        expect(trace.slices.every((q) => q.rows <= 51), isTrue);
        expect(
          trace.slices.every((q) => !q.sql.toUpperCase().contains('OFFSET')),
          isTrue,
        );
        expect((await cache.readListState()).revision, state.revision);
        expect(
          (await cache.readListState()).nextCursor?.activityAt,
          state.nextCursor?.activityAt,
        );
        expect(
          (await cache.readListState()).nextCursor?.conversationId,
          _id(1955),
        );
        expect((await cache.readUnreadState()).revision, badge.revision);
        expect((await cache.readUnreadState()).total, 37);
      },
    );

    test('empty and exact-size slices have no false continuation', () async {
      expect((await cache.readAvailableSlice()).chats, isEmpty);
      expect((await cache.readAvailableSlice()).nextCursor, isNull);
      await cache.replaceAll([_chat(1), _chat(2)]);
      final exact = await cache.readAvailableSlice(limit: 2);
      expect(exact.chats.map((c) => c.id), [_id(2), _id(1)]);
      expect(exact.nextCursor, isNull);
      final head = await cache.readAvailableSlice(limit: 1);
      final tail = await cache.readAvailableSlice(
        limit: 1,
        after: head.nextCursor,
      );
      expect(tail.chats.single.id, _id(1));
      expect(tail.nextCursor, isNull);
    });

    test(
      'prefix search normalizes Russian and escapes percent underscore and slash',
      () async {
        await cache.replaceAll([
          _chat(1, name: 'АЛЕКСЕЙ'),
          _chat(2, name: 'александр'),
          _chat(3, name: 'Миша алекс'),
          _chat(4, name: r'100%_\Test'),
          _chat(5, name: r'100xx\Test'),
          _chat(6, name: r'100%X\Test'),
          _chat(7, name: '100%_Test'),
          _chat(8, name: r'100%_\Tail'),
        ]);
        await cache.replaceAll([
          _chat(99, name: 'АЛЕКСЕЙ'),
        ], ownerUserId: 'other');
        expect(
          (await cache.readAvailableSlice(
            query: '  АлЕкС ',
          )).chats.map((c) => c.id),
          [_id(2), _id(1)],
        );
        final first = await cache.readAvailableSlice(
          query: r' 100%_\T ',
          limit: 1,
        );
        expect(first.chats.single.id, _id(8));
        expect(first.nextCursor?.query, r'100%_\t');
        final second = await cache.readAvailableSlice(
          query: r'100%_\t',
          limit: 1,
          after: first.nextCursor,
        );
        expect(second.chats.single.id, _id(4));
        expect(second.nextCursor, isNull);
        final watched = await cache
            .watchAvailableSlice(query: r'100%_\T')
            .first;
        expect(watched.chats.map((c) => c.id), [_id(8), _id(4)]);
        expect((await cache.readAvailableSlice(query: 'лекс')).chats, isEmpty);
      },
    );

    test(
      'slice limits query length and mismatched cursors are rejected',
      () async {
        for (final limit in [-1, 0, 201]) {
          await expectLater(
            cache.readAvailableSlice(limit: limit),
            throwsArgumentError,
          );
          expect(
            () => cache.watchAvailableSlice(limit: limit),
            throwsArgumentError,
          );
        }
        await expectLater(
          cache.readAvailableSlice(query: 'я' * 101),
          throwsArgumentError,
        );
        expect(
          () => cache.watchAvailableSlice(query: 'я' * 101),
          throwsArgumentError,
        );
        final wrongQuery = ChatListLocalCursor(
          query: 'different',
          activityMicros: _epoch.microsecondsSinceEpoch,
          chatId: _id(1),
          serverBacked: false,
        );
        await expectLater(
          cache.readAvailableSlice(query: 'ал', after: wrongQuery),
          throwsArgumentError,
        );
        expect(
          () => cache.watchAvailableSlice(query: 'ал', after: wrongQuery),
          throwsArgumentError,
        );
        expect((await cache.readAvailableSlice(limit: 200)).chats, isEmpty);
      },
    );

    test(
      'page activity preserves exact available order independently of preview seconds',
      () async {
        await cache.applyListPage(
          await cache.beginListRefresh(),
          ChatListPage(
            items: [
              ChatListPageItem(
                chat: _chat(1, time: _epoch),
                activityAt: _at(900),
              ),
              ChatListPageItem(
                chat: _chat(2, time: _epoch),
                activityAt: _at(800),
              ),
            ],
            query: '',
            nextCursor: null,
          ),
        );
        final first = await cache.readAvailableSlice(limit: 1);
        expect(first.chats.single.id, _id(1));
        expect(first.orderByChatId[_id(1)], _at(900).microsecondsSinceEpoch);
        expect(
          first.nextCursor?.activityMicros,
          _at(900).microsecondsSinceEpoch,
        );
        final second = await cache.readAvailableSlice(
          limit: 1,
          after: first.nextCursor,
        );
        expect(second.chats.single.id, _id(2));
        expect(second.orderByChatId[_id(2)], _at(800).microsecondsSinceEpoch);
      },
    );

    test(
      'replacement persists a preview timestamp correction within one second',
      () async {
        await cache.replaceAll([
          _chat(1, time: _at(100)),
          _chat(2, time: _at(200)),
        ]);
        expect(
          await cache.replaceAll([
            _chat(1, time: _at(300)),
            _chat(2, time: _at(200)),
          ]),
          isTrue,
        );
        final slice = await cache.readAvailableSlice();
        expect(slice.chats.map((c) => c.id), [_id(1), _id(2)]);
        expect(slice.orderByChatId[_id(1)], _at(300).microsecondsSinceEpoch);
      },
    );

    for (final covered in [false, true]) {
      test(
        'summary activity updates available order with remote coverage=$covered',
        () async {
          await cache.replaceAll([
            _chat(1, time: _epoch),
            _chat(2, time: _at(500)),
          ]);
          if (covered) {
            await cache.applyListPage(
              await cache.beginListRefresh(),
              ChatListPage(
                items: [
                  ChatListPageItem(
                    chat: _chat(2, time: _at(500)),
                    activityAt: _at(500),
                  ),
                ],
                query: '',
                nextCursor: null,
              ),
            );
          }
          final state = await cache.readListState();
          await cache.applySummaryBatch(
            {_id(1)},
            [_chat(1, time: _epoch)],
            activityByChatId: {_id(1): _at(999)},
          );
          final slice = await cache.readAvailableSlice();
          expect(slice.chats.map((c) => c.id), [_id(1), _id(2)]);
          expect(slice.orderByChatId[_id(1)], _at(999).microsecondsSinceEpoch);
          expect((await cache.readListState()).hasRemotePage, covered);
          expect((await cache.readListState()).revision, state.revision);
        },
      );
    }

    test(
      'pending preview keeps exact order while remote continuation stays unchanged',
      () async {
        await cache.replaceAll([
          _chat(1, time: _epoch),
          _chat(2, time: _at(900)),
        ]);
        await cache.applyListPage(
          await cache.beginListRefresh(),
          ChatListPage(
            items: [
              ChatListPageItem(
                chat: _chat(2, time: _at(900)),
                activityAt: _at(900),
              ),
            ],
            query: '',
            nextCursor: ChatListPageCursor(
              activityAt: _at(900),
              conversationId: _id(2),
            ),
          ),
        );
        final state = await cache.readListState();
        await cache.updateLastMessage(
          ChatMessage(
            id: 'pending',
            chatId: _id(1),
            senderId: 'owner',
            text: 'sending offline',
            timestamp: _at(901),
            isMine: true,
            status: MessageStatus.sending,
          ),
        );
        final slice = await cache.readAvailableSlice();
        expect(slice.chats.map((c) => c.id), [_id(1), _id(2)]);
        expect(slice.orderByChatId[_id(1)], _at(901).microsecondsSinceEpoch);
        expect(slice.chats.first.lastMessageId, 'pending');
        expect((await cache.readListState()).revision, state.revision);
        expect((await cache.nextListRequest())?.after?.activityAt, _at(900));
        // The page caller already merges pending previews into the Chat model.
        await cache.applyListPage(
          await cache.beginListRefresh(),
          ChatListPage(
            items: [
              ChatListPageItem(
                chat: _chat(
                  1,
                  time: _at(901),
                ).copyWith(lastMessageId: 'pending'),
                activityAt: _at(100),
              ),
            ],
            query: '',
            nextCursor: ChatListPageCursor(
              activityAt: _at(100),
              conversationId: _id(1),
            ),
          ),
        );
        expect(
          (await cache.readAvailableSlice()).orderByChatId[_id(1)],
          _at(901).microsecondsSinceEpoch,
        );
        expect((await cache.nextListRequest())?.after?.activityAt, _at(100));
      },
    );

    test(
      'slice watcher emits order-only changes and retains its captured owner',
      () async {
        await cache.replaceAll([_chat(1), _chat(2), _chat(3)]);
        final iterator = StreamIterator(cache.watchAvailableSlice(limit: 2));
        addTearDown(iterator.cancel);
        final before = await _next(iterator);
        expect(before.chats.map((c) => c.id), [_id(3), _id(2)]);
        owner = 'other';
        await cache.replaceAll([_chat(99)]);
        final next = _next(iterator);
        // Same mapped Chat, same ID and same cursor ID: only exact order changes.
        await (db.update(db.cachedChats)..where(
              (t) => t.ownerUserId.equals('owner') & t.id.equals(_id(3)),
            ))
            .write(
              CachedChatsCompanion(
                listOrderMicros: Value(_at(777).microsecondsSinceEpoch),
              ),
            );
        final changed = await next;
        expect(changed.chats, before.chats);
        expect(changed.orderByChatId[_id(3)], _at(777).microsecondsSinceEpoch);
        expect(changed.nextCursor?.chatId, before.nextCursor?.chatId);
        expect(changed.chats.every((c) => c.id != _id(99)), isTrue);
        final removed = _next(iterator);
        await cache.remove({_id(3)}, ownerUserId: 'owner');
        expect((await removed).chats.map((c) => c.id), [_id(2), _id(1)]);
      },
    );

    test(
      'tail watcher reflects insertion and removal beyond a fixed seek cursor',
      () async {
        await cache.replaceAll([_chat(3), _chat(2)]);
        final head = await cache.readAvailableSlice(limit: 1);
        final iterator = StreamIterator(
          cache.watchAvailableSlice(limit: 1, after: head.nextCursor),
        );
        addTearDown(iterator.cancel);
        expect((await _next(iterator)).chats.single.id, _id(2));
        final removed = _next(iterator);
        await cache.remove({_id(2)});
        expect((await removed).chats, isEmpty);
        final inserted = _next(iterator);
        await cache.applySummaryBatch({_id(1)}, [_chat(1)]);
        final tail = await inserted;
        expect(tail.chats.single.id, _id(1));
        expect(tail.nextCursor, isNull);
      },
    );

    test(
      'ID reads batch 405 requests and map only owner-scoped available rows',
      () async {
        await cache.replaceAll([for (var n = 0; n < 2005; n++) _chat(n)]);
        await _coverHead(cache);
        await cache.replaceAll([_chat(9000)], ownerUserId: 'other');
        trace.clear();
        media.paths = 0;
        // readAvailableItems is the current production ID-read API.
        final items = await cache.readAvailableItems({
          for (var n = 0; n < 403; n++) _id(n),
          _id(9000),
          'missing',
        });
        expect(
          items.map((i) => i.chat.id),
          unorderedEquals([for (var n = 0; n < 403; n++) _id(n)]),
        );
        expect(
          items.every(
            (i) =>
                i.orderMicros ==
                _at(
                  int.parse(i.chat.id.substring(5)) ~/ 3,
                ).microsecondsSinceEpoch,
          ),
          isTrue,
        );
        expect(
          items.first.chat.cachedAvatarPath,
          startsWith('/cache/owner/avatars/'),
        );
        expect(media.paths, 403);
        expect(trace.ids, hasLength(2));
        expect(trace.ids.every((q) => q.rows <= 400), isTrue);
        for (final query in trace.ids) {
          final plan = await db.executor.runSelect(
            'EXPLAIN QUERY PLAN ${query.sql}',
            query.args,
          );
          expect(plan.toString(), contains('owner_user_id=? AND id=?'));
        }
        trace.clear();
        expect(await cache.readAvailableItems({}), isEmpty);
        expect(trace.ids, isEmpty);
        expect(
          (await cache.readAvailableItems({
            _id(9000),
          }, ownerUserId: 'other')).single.chat.id,
          _id(9000),
        );
      },
    );

    test(
      'missing observed IDs appear without claiming remote coverage',
      () async {
        final iterator = StreamIterator(cache.watchAvailableIds({_id(1)}));
        addTearDown(iterator.cancel);
        expect(await _next(iterator), isEmpty);
        final inserted = _next(iterator);
        await cache.applySummaryBatch({_id(1)}, [_chat(1, time: _at(123))]);
        final item = (await inserted).single;
        expect(item.chat.id, _id(1));
        expect(item.orderMicros, _at(123).microsecondsSinceEpoch);
        expect((await cache.readListState()).hasRemotePage, isFalse);
        expect(await db.select(db.cachedChatListEntries).get(), isEmpty);
      },
    );

    test(
      'ID watcher is bounded to 150 and observes metadata deletion and order',
      () async {
        await cache.replaceAll([for (var n = 0; n < 2005; n++) _chat(n)]);
        await _coverHead(cache);
        final ids = {for (var n = 0; n < 150; n++) _id(n)};
        expect(
          () => cache.watchAvailableIds({...ids, _id(150)}),
          throwsArgumentError,
        );
        expect(await cache.watchAvailableIds({}).single, isEmpty);
        trace.clear();
        media.paths = 0;
        final iterator = StreamIterator(cache.watchAvailableIds(ids));
        addTearDown(iterator.cancel);
        final first = await _next(iterator);
        expect(first.map((i) => i.chat.id), unorderedEquals(ids));
        expect(media.paths, 150);
        owner = 'other';
        final changed = _next(iterator);
        await cache.applySummaryBatch(
          {_id(1)},
          [
            _chat(
              1,
              time: _at(123456),
            ).copyWith(lastMessage: 'changed', unreadCount: 42),
          ],
          ownerUserId: 'owner',
        );
        final updated = (await changed).singleWhere((i) => i.chat.id == _id(1));
        expect(updated.chat.lastMessage, 'changed');
        expect(updated.chat.unreadCount, 42);
        expect(updated.orderMicros, _at(123456).microsecondsSinceEpoch);
        final deleted = _next(iterator);
        await cache.remove({_id(1)}, ownerUserId: 'owner');
        expect(
          (await deleted).map((i) => i.chat.id),
          unorderedEquals(ids.difference({_id(1)})),
        );
        expect(trace.ids.every((q) => q.rows <= 150), isTrue);
        expect(trace.ids.every((q) => q.args.last == 'owner'), isTrue);
      },
    );

    test(
      'nullable legacy order falls back to seconds and ties seek by descending ID',
      () async {
        await cache.replaceAll([_chat(1), _chat(2), _chat(3, time: _at(1))]);
        await (db.update(db.cachedChats)
              ..where((t) => t.id.isIn([_id(1), _id(2)])))
            .write(const CachedChatsCompanion(listOrderMicros: Value(null)));
        final ids = <String>[];
        ChatListLocalCursor? cursor;
        do {
          final slice = await cache.readAvailableSlice(limit: 1, after: cursor);
          ids.add(slice.chats.single.id);
          cursor = slice.nextCursor;
        } while (cursor != null && ids.length < 4);
        expect(ids, [_id(3), _id(2), _id(1)]);
        final items = await cache.readAvailableItems({_id(1), _id(3)});
        expect(
          items.singleWhere((i) => i.chat.id == _id(1)).orderMicros,
          _epoch.microsecondsSinceEpoch,
        );
        expect(
          items.singleWhere((i) => i.chat.id == _id(3)).orderMicros,
          _at(1).microsecondsSinceEpoch,
        );
      },
    );

    test(
      'actual deep continuation SQL seeks into the order index with bounded output',
      () async {
        await cache.replaceAll([for (var n = 0; n < 2005; n++) _chat(n)]);
        trace.clear();
        media.paths = 0;
        final slice = await cache.readAvailableSlice(
          limit: 17,
          after: ChatListLocalCursor(
            query: '',
            activityMicros: _at(100 ~/ 3).microsecondsSinceEpoch,
            chatId: _id(100),
            serverBacked: false,
          ),
        );
        expect(slice.chats.map((c) => c.id), [
          for (var n = 99; n >= 83; n--) _id(n),
        ]);
        expect(media.paths, 17);
        final query = trace.slices.single;
        expect(
          query.rows,
          18,
          reason: 'Only limit + one sentinel may cross into Dart',
        );
        expect(query.args.last, 18);
        expect(query.sql.toUpperCase(), isNot(contains('OFFSET')));
        final plan = await db.executor.runSelect(
          'EXPLAIN QUERY PLAN ${query.sql}',
          query.args,
        );
        expect(
          plan.toString(),
          contains('cached_chats_owner_available_order_idx'),
        );
        expect(plan.toString(), isNot(contains('TEMP B-TREE')));
        // Merely naming the index is insufficient: an owner-only seek scans all
        // newer chats on every continuation. Require activity in the range seek.
        final details = plan.map((r) => r['detail'].toString()).join('\n');
        expect(
          details,
          contains('<'),
          reason:
              'Continuation must seek by activity, not scan the owner prefix',
        );
      },
    );
  });

  for (final count in [0, 2005]) {
    test(
      'actual v27 upgrade preserves $count retained chats and cache payloads',
      () async {
        final connection = sqlite.sqlite3.openInMemory();
        var db = AppDatabase.forTesting(
          NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
        );
        try {
          var cache = ChatsCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          await cache.replaceAll([
            for (var n = 0; n < count; n++) _chat(n, time: _epoch),
          ]);
          await cache.replaceAll([
            _chat(1, time: _epoch),
          ], ownerUserId: 'other');
          if (count > 0) {
            await _coverHead(cache);
            // v27 has exact positions only for covered rows. A search entry
            // must not override the canonical main-list order during migration.
            await db
                .into(db.cachedChatListEntries)
                .insert(
                  CachedChatListEntriesCompanion.insert(
                    ownerUserId: 'owner',
                    query: 'ал',
                    chatId: _id(0),
                    activityMicros: _at(999999).microsecondsSinceEpoch,
                  ),
                );
            await db
                .into(db.cachedChatListEntries)
                .insert(
                  CachedChatListEntriesCompanion.insert(
                    ownerUserId: 'other',
                    query: '',
                    chatId: _id(1),
                    activityMicros: _at(123456).microsecondsSinceEpoch,
                  ),
                );
            await cache.updateLastMessage(
              ChatMessage(
                id: 'pending',
                chatId: _id(2004),
                senderId: 'owner',
                text: 'pending newer than remote',
                timestamp: _epoch.add(const Duration(seconds: 2)),
                isMine: true,
                status: MessageStatus.sending,
              ),
            );
          }
          final messages = ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          await messages.upsertMessage(
            ChatMessage(
              id: 'media',
              chatId: _id(0),
              senderId: 'peer-0',
              text: 'keep media',
              timestamp: _at(654321),
              isMine: false,
              type: MessageType.image,
              mediaUrls: const ['/cache/images/local.jpg'],
              mediaStoragePaths: const ['conversation/peer/image.jpg'],
              audioUrl: '/cache/audio/local.m4a',
              audioStoragePath: 'conversation/peer/audio.m4a',
            ),
          );
          await messages.putPendingChatDeletion(
            id: 'delete',
            chatId: 'pending-delete',
            clearedAt: _epoch,
          );
          await db
              .into(db.cachedProfilePhotos)
              .insert(
                CachedProfilePhotosCompanion.insert(
                  userId: 'owner',
                  position: 0,
                  storagePath: const Value('owner/profile.jpg'),
                ),
              );
          // Close Drift before constructing the real previous schema. Changing
          // only user_version would leave the new column in place and skip the
          // migration branch this test is intended to exercise.
          await db.close();
          connection.execute(
            'DROP INDEX cached_chats_owner_available_order_idx',
          );
          connection.execute(
            'ALTER TABLE cached_chats DROP COLUMN list_order_micros',
          );
          connection.execute('PRAGMA user_version=27');
          expect(
            connection
                .select('PRAGMA table_info(cached_chats)')
                .map((r) => r['name']),
            isNot(contains('list_order_micros')),
          );
          expect(
            connection.select('PRAGMA user_version').single['user_version'],
            27,
          );
          final tables = <String, String>{
            'cached_chats': 'owner_user_id,id',
            'cached_chat_list_entries': 'owner_user_id,query,chat_id',
            'cached_chat_list_states': 'owner_user_id,query',
            'cached_chat_unread_totals': 'owner_user_id',
            'cached_messages': 'owner_user_id,id',
            'pending_chat_operations': 'owner_user_id,id',
            'cached_profile_photos': 'user_id,position',
          };
          final before = {
            for (final entry in tables.entries)
              entry.key: _snapshot(connection, entry.key, entry.value),
          };
          db = AppDatabase.forTesting(
            NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
          );
          final media = _Media(db);
          cache = ChatsCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
            mediaCache: media,
          );
          final slice = await cache.readAvailableSlice(limit: 1);
          expect(
            connection.select('PRAGMA user_version').single['user_version'],
            db.schemaVersion,
          );
          expect(db.schemaVersion, 30);
          for (final entry in tables.entries) {
            final after = _snapshot(connection, entry.key, entry.value);
            if (entry.key == 'cached_chats') {
              for (final row in after) {
                row.remove('list_order_micros');
              }
            }
            expect(
              after,
              before[entry.key],
              reason: '${entry.key} changed during migration',
            );
          }
          if (count == 0) {
            expect(slice.chats, isEmpty);
            expect(slice.nextCursor, isNull);
            expect((await cache.readListState()).hasRemotePage, isFalse);
            expect((await cache.readUnreadState()).total, isNull);
          } else {
            expect(slice.chats.single.id, _id(2004));
            expect(
              slice.orderByChatId[_id(2004)],
              _epoch.add(const Duration(seconds: 2)).microsecondsSinceEpoch,
            );
            expect(
              slice.chats.single.cachedAvatarPath,
              '/cache/owner/avatars/peer-2004/avatar.jpg',
            );
            final tail = await cache.readAvailableSlice(
              limit: 200,
              after: slice.nextCursor,
            );
            expect(tail.chats.take(49).map((c) => c.id), [
              for (var n = 2003; n >= 1955; n--) _id(n),
            ]);
            expect(
              tail.orderByChatId[_id(2003)],
              _at(2003 ~/ 3).microsecondsSinceEpoch,
            );
            final legacy = (await cache.readAvailableItems({_id(0)})).single;
            expect(legacy.orderMicros, _epoch.microsecondsSinceEpoch);
            expect(
              (await cache.readAvailableItems({
                _id(1),
              }, ownerUserId: 'other')).single.orderMicros,
              _at(123456).microsecondsSinceEpoch,
            );
            expect(
              (await cache.readListState()).nextCursor?.activityAt,
              _at(1955 ~/ 3),
            );
            expect(
              (await cache.readListState()).nextCursor?.conversationId,
              _id(1955),
            );
            expect((await cache.readUnreadState()).total, 37);
            expect(
              connection
                  .select(
                    "SELECT COUNT(*) AS n FROM cached_chats WHERE owner_user_id='owner'",
                  )
                  .single['n'],
              2005,
            );
          }
          final restored = await ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          ).readMessage('media', currentUserId: 'owner');
          expect(restored?.mediaUrls, ['/cache/images/local.jpg']);
          expect(restored?.mediaStoragePaths, ['conversation/peer/image.jpg']);
          expect(restored?.audioUrl, '/cache/audio/local.m4a');
          expect(restored?.audioStoragePath, 'conversation/peer/audio.m4a');
          expect(
            connection
                .select("SELECT name FROM sqlite_master WHERE type='index'")
                .map((r) => r['name']),
            contains('cached_chats_owner_available_order_idx'),
          );
        } finally {
          await db.close();
          connection.close();
        }
      },
    );
  }
}

List<Map<String, Object?>> _snapshot(
  sqlite.Database db,
  String table,
  String order,
) => [
  for (final row in db.select('SELECT * FROM $table ORDER BY $order'))
    Map<String, Object?>.from(row),
];

class _Media extends MediaCacheService {
  _Media(AppDatabase db) : super(database: db);
  int paths = 0;

  @override
  Future<void> prepareLocalPaths() async {}

  @override
  String? localStorageFilePath({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) {
    paths++;
    return '/cache/$ownerUserId/$bucket/$storagePath';
  }
}

class _Selected {
  _Selected(this.sql, List<Object?> args, this.rows) : args = List.of(args);
  final String sql;
  final List<Object?> args;
  final int rows;
}

class _SelectTrace extends QueryInterceptor {
  final slices = <_Selected>[];
  final ids = <_Selected>[];

  void clear() {
    slices.clear();
    ids.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> parameters,
  ) async {
    final rows = await executor.runSelect(statement, parameters);
    if (!statement.startsWith('EXPLAIN')) {
      if (statement.contains('AS order_micros FROM cached_chats c')) {
        slices.add(_Selected(statement, parameters, rows.length));
      }
      if (statement.contains('requested(id)') &&
          statement.contains('CROSS JOIN cached_chats c')) {
        ids.add(_Selected(statement, parameters, rows.length));
      }
    }
    return rows;
  }
}
