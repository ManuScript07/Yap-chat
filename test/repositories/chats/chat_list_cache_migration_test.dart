import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  for (final count in [0, 1001, 10000]) {
    test(
      'v26 to current retains $count chats, media and message cache',
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
            for (var i = 0; i < count; i++)
              Chat(
                id: 'chat-${i.toString().padLeft(5, '0')}',
                peerId: 'peer-$i',
                userName: i.isEven ? 'АЛЕКСЕЙ $i' : 'Мария $i',
                avatarStoragePath: 'peer-$i/avatar.jpg',
                lastMessage: 'message $i',
                lastMessageTime: DateTime.utc(2026),
                unreadCount: 1,
                isOnline: false,
                isLastMessageFromMe: false,
              ),
          ]);
          await cache.replaceAll([
            Chat(
              id: 'other',
              peerId: 'peer',
              userName: 'Другой владелец',
              lastMessage: 'keep',
              lastMessageTime: DateTime.utc(2026),
              unreadCount: 42,
              isOnline: false,
              isLastMessageFromMe: false,
            ),
          ], ownerUserId: 'other');
          final messages = ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          await messages.upsertMessages([
            ChatMessage(
              id: 'message',
              chatId: 'chat-00000',
              senderId: 'peer',
              text: 'original',
              timestamp: DateTime.utc(2026),
              isMine: false,
            ),
          ]);
          await db
              .into(db.cachedProfilePhotos)
              .insert(
                CachedProfilePhotosCompanion.insert(
                  userId: 'owner',
                  position: 0,
                  bytes: Value(Uint8List.fromList([1, 2, 3])),
                ),
              );
          // SQLite rowid is not guaranteed to start at one in imported caches.
          await db.customStatement(
            "UPDATE cached_chats SET rowid=-5 WHERE id='other'",
          );
          for (final table in [
            'cached_chat_list_entries',
            'cached_chat_list_states',
            'cached_chat_unread_totals',
          ]) {
            await db.customStatement('DROP TABLE $table');
          }
          await db.customStatement('DROP INDEX cached_chats_owner_name_idx');
          await db.customStatement(
            'DROP INDEX cached_chats_owner_available_order_idx',
          );
          await db.customStatement(
            'ALTER TABLE cached_chats DROP COLUMN list_order_micros',
          );
          await db.customStatement(
            'ALTER TABLE cached_chats DROP COLUMN peer_display_name_search',
          );
          await db.customStatement('PRAGMA user_version=26');
          await db.close();
          final started = Stopwatch()..start();
          db = AppDatabase.forTesting(
            NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
          );
          cache = ChatsCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          final slice = await cache.readListSlice();
          started.stop();
          expect(slice.chats.length, count.clamp(0, 50));
          expect(slice.serverBacked, false);
          expect((await cache.readListState()).hasRemotePage, false);
          expect((await cache.readUnreadState()).total, isNull);
          expect((await cache.read()).length, count);
          expect((await cache.readListSlice(query: '  ЛеКС ')).chats.length, 0);
          expect(
            (await cache.readListSlice(query: '  АлЕкСЕЙ ')).chats.length,
            (count ~/ 2).clamp(0, 50),
          );
          if (count > 0) {
            expect(slice.chats.first.avatarStoragePath, startsWith('peer-'));
          }
          expect(
            (await cache.read(ownerUserId: 'other')).single.unreadCount,
            42,
          );
          expect(
            (await cache.readListSlice(
              query: 'Другой',
              ownerUserId: 'other',
            )).chats.single.id,
            'other',
          );
          expect(
            (await ChatCacheDataSource(
              database: db,
              userIdProvider: () => 'owner',
            ).readMessage('message', currentUserId: 'owner'))?.text,
            'original',
          );
          expect((await db.select(db.cachedProfilePhotos).get()).single.bytes, [
            1,
            2,
            3,
          ]);
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            db.schemaVersion,
          );
          stdout.writeln(
            'CHAT_LIST_V26_UPGRADE chats=$count elapsed_ms=${started.elapsedMicroseconds / 1000}',
          );
        } finally {
          await db.close();
          connection.close();
        }
      },
    );
  }

  test(
    'confirmed cursors and global badge survive a physical reopen',
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
        final activity = DateTime.parse('2026-10-26T10:11:12.123456Z');
        final chat = Chat(
          id: 'id',
          peerId: 'peer',
          userName: 'Имя',
          avatarStoragePath: 'peer/avatar.jpg',
          lastMessage: 'text',
          lastMessageTime: activity,
          unreadCount: 1,
          isOnline: false,
          isLastMessageFromMe: false,
        );
        await cache.applyListPage(
          await cache.beginListRefresh(),
          ChatListPage(
            items: [ChatListPageItem(chat: chat, activityAt: activity)],
            query: '',
            unreadTotal: 123,
            nextCursor: ChatListPageCursor(
              activityAt: activity,
              conversationId: 'id',
            ),
          ),
        );
        final oldRequest = (await cache.nextListRequest())!;
        await db.close();
        db = AppDatabase.forTesting(
          NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
        );
        cache = ChatsCacheDataSource(
          database: db,
          userIdProvider: () => 'owner',
        );
        expect(
          (await cache.readListSlice()).chats.single.avatarStoragePath,
          'peer/avatar.jpg',
        );
        expect((await cache.readUnreadState()).total, 123);
        final next = (await cache.nextListRequest())!;
        expect(next.after!.activityAt, activity);
        expect(next.revision, oldRequest.revision);
        expect(next.unreadRevision, oldRequest.unreadRevision);
        expect((await cache.readListState()).hasRemotePage, true);
      } finally {
        await db.close();
        connection.close();
      }
    },
  );
}
