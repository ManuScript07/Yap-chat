import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';

void main() {
  late AppDatabase db;
  late ChatCacheDataSource cache;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = ChatCacheDataSource(database: db, userIdProvider: () => 'owner');
  });
  tearDown(() => db.close());

  test(
    '10000 cached messages: live head maps only 60 rows using cursor index',
    () async {
      await db.batch((batch) {
        batch.insertAll(db.cachedMessages, [
          for (var i = 0; i < 10000; i++)
            CachedMessagesCompanion.insert(
              ownerUserId: 'owner',
              id: 'm$i',
              chatId: 'chat',
              senderId: 'peer',
              messageText: '$i',
              timestamp: _m(i).timestamp,
              timestampMicros: Value(_m(i).timestamp.microsecondsSinceEpoch),
              status: 'sent',
              type: 'text',
              mediaUrlsJson: i < 60 ? '[]' : 'invalid-old-json',
              mediaStoragePathsJson: '[]',
              audioWaveformJson: '[]',
              isPending: false,
              cachedAt: DateTime(2026),
            ),
        ]);
      });
      final head = await cache
          .watchMessages('chat', currentUserId: 'owner', limit: 60)
          .first;
      expect(head.map((m) => m.id), [for (var i = 0; i < 60; i++) 'm$i']);
      final plan = await db.customSelect('''EXPLAIN QUERY PLAN
      SELECT * FROM cached_messages WHERE owner_user_id = 'owner' AND chat_id = 'chat'
      ORDER BY timestamp_micros DESC, id DESC LIMIT 60''').get();
      final details = plan.map((r) => r.read<String>('detail')).join(' ');
      expect(details, contains('cached_messages_owner_chat_cursor_idx'));
      expect(details, isNot(contains('TEMP B-TREE')));
      final olderPlan = await db.customSelect('''EXPLAIN QUERY PLAN
      SELECT * FROM cached_messages WHERE owner_user_id = 'owner' AND chat_id = 'chat'
      AND (timestamp_micros, id) < (12345, 'boundary')
      ORDER BY timestamp_micros DESC, id DESC LIMIT 60''').get();
      expect(
        olderPlan.map((r) => r.read<String>('detail')).join(' '),
        contains('(timestamp_micros,id)<(?,?)'),
      );
    },
  );

  test(
    'local keyset pages keep microseconds, stable IDs, and bounded size',
    () async {
      final messages = [for (var i = 0; i < 180; i++) _m(i)];
      await cache.replaceRecentMessages('chat', messages.take(60).toList());
      await cache.storeHistoryPage(
        'chat',
        messages.skip(60).take(60).toList(),
        ownerUserId: 'owner',
        boundary: messages[59],
        older: true,
      );
      final page = await cache.readHistoryPage(
        'chat',
        messages[59],
        ownerUserId: 'owner',
        older: true,
      );
      expect(page, messages.skip(60).take(60).toList());
      final newer = await cache.readHistoryPage(
        'chat',
        messages[119],
        ownerUserId: 'owner',
        older: false,
      );
      expect(newer, messages.skip(59).take(60).toList());
      expect(
        await cache.readHistoryPage(
          'chat',
          messages[119],
          ownerUserId: 'owner',
          older: true,
        ),
        isNull,
      );
    },
  );

  test(
    'a disjoint offline cache cannot silently bridge a missing page',
    () async {
      final messages = [for (var i = 0; i < 240; i++) _m(i)];
      await cache.replaceRecentMessages('chat', messages.skip(180).toList());
      await cache.replaceRecentMessages('chat', messages.take(60).toList());
      expect(
        await cache.readHistoryPage(
          'chat',
          messages[59],
          ownerUserId: 'owner',
          older: true,
        ),
        isNull,
      );
      for (var start = 60; start < 240; start += 60) {
        await cache.storeHistoryPage(
          'chat',
          messages.skip(start).take(60).toList(),
          ownerUserId: 'owner',
          boundary: messages[start - 1],
          older: true,
        );
      }
      expect(await db.select(db.cachedChatHistoryRanges).get(), hasLength(1));
      expect(
        await cache.readHistoryPage(
          'chat',
          messages[179],
          ownerUserId: 'owner',
          older: true,
        ),
        messages.skip(180).toList(),
      );
    },
  );

  test(
    'deleted boundary stays usable and confirmed end requires no request',
    () async {
      final messages = [for (var i = 0; i < 95; i++) _m(i)];
      await cache.replaceRecentMessages('chat', messages.take(60).toList());
      await cache.storeHistoryPage(
        'chat',
        messages.skip(60).toList(),
        ownerUserId: 'owner',
        boundary: messages[59],
        older: true,
      );
      await cache.removeMessages('chat', {
        messages[59].id,
      }, ownerUserId: 'owner');
      expect(
        await cache.readHistoryPage(
          'chat',
          messages[59],
          ownerUserId: 'owner',
          older: true,
        ),
        messages.skip(60).toList(),
      );
      expect(
        await cache.readHistoryPage(
          'chat',
          messages.last,
          ownerUserId: 'owner',
          older: true,
        ),
        isEmpty,
      );
    },
  );

  test(
    'owner isolation, pending overlay, reactions and conversation clear',
    () async {
      final messages = [for (var i = 0; i < 95; i++) _m(i)];
      await cache.replaceRecentMessages('chat', messages.take(60).toList());
      await cache.storeHistoryPage(
        'chat',
        messages.skip(60).toList(),
        ownerUserId: 'owner',
        boundary: messages[59],
        older: true,
      );
      await cache.upsertMessage(
        _m(70).copyWith(
          senderId: 'owner',
          isMine: true,
          status: MessageStatus.error,
        ),
        isPending: true,
      );
      final page = await cache.readHistoryPage(
        'chat',
        messages[59],
        ownerUserId: 'owner',
        older: true,
      );
      expect(
        page!.firstWhere((m) => m.id == 'm70').status,
        MessageStatus.error,
      );
      expect(
        await cache.readHistoryPage(
          'chat',
          messages[59],
          ownerUserId: 'other',
          older: true,
        ),
        isNull,
      );
      await cache.clearConversations({'chat'});
      expect(await db.select(db.cachedChatHistoryRanges).get(), isEmpty);
    },
  );

  test(
    'legacy cache without coverage is never advertised as continuous',
    () async {
      await cache.upsertMessages([for (var i = 0; i < 200; i++) _m(i)]);
      expect(
        await cache.readHistoryPage(
          'chat',
          _m(59),
          ownerUserId: 'owner',
          older: true,
        ),
        isNull,
      );
      expect(
        await cache
            .watchMessages('chat', currentUserId: 'owner', limit: 60)
            .first,
        hasLength(60),
      );
    },
  );

  test(
    'version 25 migration retains rows and marks rounded cursors unknown',
    () async {
      final connection = sqlite.sqlite3.openInMemory();
      var migrated = AppDatabase.forTesting(
        NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
      );
      try {
        var oldCache = ChatCacheDataSource(
          database: migrated,
          userIdProvider: () => 'owner',
        );
        await oldCache.upsertMessages([_m(0)]);
        await migrated.customStatement(
          'DROP INDEX cached_messages_owner_chat_cursor_idx',
        );
        await migrated.customStatement(
          'ALTER TABLE cached_messages DROP COLUMN timestamp_micros',
        );
        await migrated.customStatement(
          'ALTER TABLE cached_messages DROP COLUMN has_exact_timestamp',
        );
        await migrated.customStatement('DROP TABLE cached_chat_history_ranges');
        await migrated.customStatement('PRAGMA user_version = 25');
        await migrated.close();
        migrated = AppDatabase.forTesting(
          NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
        );
        oldCache = ChatCacheDataSource(
          database: migrated,
          userIdProvider: () => 'owner',
        );
        expect(
          (await oldCache.readMessage('m0', currentUserId: 'owner'))?.text,
          'message 0',
        );
        expect(
          await oldCache.hasExactCursor('m0', ownerUserId: 'owner'),
          isFalse,
        );
        expect(
          await migrated.select(migrated.cachedChatHistoryRanges).get(),
          isEmpty,
        );
      } finally {
        await migrated.close();
        connection.close();
      }
    },
  );
}

ChatMessage _m(int index) => ChatMessage(
  id: 'm$index',
  chatId: 'chat',
  senderId: 'peer',
  text: 'message $index',
  timestamp: DateTime.utc(
    2026,
    10,
    18,
    12,
  ).subtract(Duration(microseconds: index * 1001)).toLocal(),
  isMine: false,
);
