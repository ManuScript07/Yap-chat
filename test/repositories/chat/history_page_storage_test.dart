import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

import 'support/support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  for (final older in [true, false]) {
    for (final count in [0, 1, 17, 59, 60]) {
      for (final variation in [0, 1, 2]) {
        test(
          'legacy equivalence: older=$older count=$count v=$variation',
          () async {
            final before = _Harness();
            final after = _Harness();
            addTearDown(before.db.close);
            addTearDown(after.db.close);
            final all = _messages(160);
            final boundary = all[70 + variation];
            final candidates = all.where((m) {
              final comparison = ChatHistoryCursor.of(
                m,
              ).compareTo(ChatHistoryCursor.of(boundary));
              return (older ? comparison < 0 : comparison > 0) &&
                  int.parse(m.id.substring(1)) % 11 != variation;
            }).toList();
            // Newer server pages return the nearest 60, still in descending order.
            final selected = older
                ? candidates.take(count).toList()
                : candidates.reversed.take(count).toList().reversed.toList();
            final page = selected.map(_remote).toList();
            for (final h in [before, after]) {
              await _seedRich(h, all, variation);
              if (variation == 2 && selected.isNotEmpty) {
                await h.cache.removeMessages('chat', {selected.first.id});
              }
            }
            await storeHistoryPageReference(
              before.db,
              before.cache,
              'chat',
              page,
              ownerUserId: 'owner',
              boundary: boundary,
              older: older,
            );
            await after.cache.storeHistoryPage(
              'chat',
              page,
              ownerUserId: 'owner',
              boundary: boundary,
              older: older,
            );
            expect(await _snapshot(after.db), await _snapshot(before.db));
          },
        );
      }
    }
  }

  test(
    'large missing tail is fully removed without unbounded SQL parameters',
    () async {
      final h = _Harness();
      addTearDown(h.db.close);
      final all = _messages(1450);
      await _seedRich(h, all, 1);
      final pending = all[1400];
      await h.cache.upsertMessage(pending, isPending: true);
      final outsideReply = all.first.copyWith(replyTo: _reply(all.last));
      await h.cache.upsertMessage(outsideReply);
      final pendingIds =
          (await (h.db.select(h.db.cachedMessages)..where(
                    (t) =>
                        t.ownerUserId.equals('owner') &
                        t.chatId.equals('chat') &
                        t.isPending,
                  ))
                  .get())
              .map((r) => r.id)
              .toSet();
      await h.cache.storeHistoryPage(
        'chat',
        const [],
        ownerUserId: 'owner',
        boundary: all[40],
        older: true,
      );
      final remaining = await h.cache
          .watchMessages('chat', currentUserId: 'owner')
          .first;
      expect(remaining.any((m) => m.id == pending.id), isTrue);
      expect(
        remaining
            .where(
              (m) =>
                  ChatHistoryCursor.of(
                    m,
                  ).compareTo(ChatHistoryCursor.of(all[40])) <
                  0,
            )
            .map((m) => m.id),
        unorderedEquals(
          pendingIds.where((id) => all.indexWhere((m) => m.id == id) > 40),
        ),
      );
      expect(remaining.first.replyTo, isNull);
      expect(
        await h.cache.readReactionState(all.last.id, ownerUserId: 'owner'),
        const MessageReactionState(),
      );
      expect(
        await h.cache.readPendingReaction(all.last.id, ownerUserId: 'owner'),
        isNull,
      );
      expect(
        await h.cache.readMessage(all.last.id, currentUserId: 'other'),
        isNotNull,
      );
      final otherChat = await h.cache.readMessage(
        'foreign',
        currentUserId: 'owner',
      );
      expect(otherChat!.replyTo!.messageId, all.last.id);
      expect(
        (await h.db.select(h.db.cachedChatHistoryRanges).get())
            .single
            .reachesStart,
        isTrue,
      );
    },
  );

  test(
    'failure in coverage rolls back page, deletions, replies and reactions',
    () async {
      final trace = _Trace();
      final h = _Harness(trace);
      addTearDown(h.db.close);
      final all = _messages(120);
      await _seedRich(h, all, 0);
      final before = await _snapshot(h.db);
      trace.failCoverage = true;
      await expectLater(
        h.cache.storeHistoryPage(
          'chat',
          [_remote(all[70])],
          ownerUserId: 'owner',
          boundary: all[60],
          older: true,
        ),
        throwsStateError,
      );
      trace.failCoverage = false;
      expect(await _snapshot(h.db), before);
      // Retrying must work; failed cleanup must not create process tombstones.
      await h.cache.storeHistoryPage(
        'chat',
        [_remote(all[70])],
        ownerUserId: 'owner',
        boundary: all[60],
        older: true,
      );
      expect(
        await h.cache.readMessage(all[118].id, currentUserId: 'owner'),
        isNull,
      );
      expect(
        await h.cache.readMessage(all[70].id, currentUserId: 'owner'),
        isNotNull,
      );
    },
  );

  test(
    'no absences: one bounded range lookup, no cleanup; PK media lookup',
    () async {
      final trace = _Trace();
      final h = _Harness(trace);
      addTearDown(h.db.close);
      final all = _messages(240);
      await h.cache.upsertMessages(all);
      for (final older in [true, false]) {
        trace.statements.clear();
        trace.enabled = true;
        await h.cache.storeHistoryPage(
          'chat',
          all.sublist(61, 121).map(_remote).toList(),
          ownerUserId: 'owner',
          boundary: older ? all[60] : all[121],
          older: older,
        );
        trace.enabled = false;
        expect(
          trace.statements.where(
            (s) =>
                (s.sql.startsWith('DELETE') || s.sql.startsWith('UPDATE')) &&
                !s.sql.contains('cached_chat_history_ranges'),
          ),
          isEmpty,
        );
        final missing = trace.statements
            .where((s) => s.sql.contains('NOT IN'))
            .single;
        expect(missing.sql, contains('LIMIT 400'));
        final plan = await h.db.executor.runSelect(
          'EXPLAIN QUERY PLAN ${missing.sql}',
          missing.args,
        );
        final details = plan.map((r) => r['detail']).join(' ');
        expect(details, contains('timestamp_micros,id)>(?,?)'));
        expect(details, contains('timestamp_micros,id)<(?,?)'));
        final media = trace.statements.first;
        expect(media.sql, isNot(contains('chat_id =')));
        final mediaPlan = await h.db.executor.runSelect(
          'EXPLAIN QUERY PLAN ${media.sql}',
          media.args,
        );
        expect(
          mediaPlan.map((r) => r['detail']).join(' '),
          contains('sqlite_autoindex_cached_messages_1'),
        );
      }
    },
  );

  test(
    'same-owner foreign chat is filtered before corrupt media is decoded',
    () async {
      final h = _Harness();
      addTearDown(h.db.close);
      final original = _messages(1).single;
      await h.cache.upsertMessage(original.copyWith(chatId: 'elsewhere'));
      await h.db.customStatement(
        "UPDATE cached_messages SET media_urls_json='invalid' WHERE id=?",
        [original.id],
      );
      await h.cache.storeHistoryPage(
        'chat',
        [_remote(original)],
        ownerUserId: 'owner',
        boundary: original.copyWith(
          timestamp: original.timestamp.add(const Duration(seconds: 1)),
        ),
        older: true,
      );
      expect(
        (await h.cache.readMessage(
          original.id,
          currentUserId: 'owner',
        ))!.mediaUrls,
        isEmpty,
      );
    },
  );

  test(
    'mid-cleanup failure restores metadata and leaves no temporary table',
    () async {
      final trace = _Trace();
      final h = _Harness(trace);
      addTearDown(h.db.close);
      final all = _messages(1450);
      await _seedRich(h, all, 0);
      final before = await _snapshot(h.db);
      trace.failCleanup = true;
      await expectLater(
        h.cache.storeHistoryPage(
          'chat',
          const [],
          ownerUserId: 'owner',
          boundary: all[60],
          older: true,
        ),
        throwsStateError,
      );
      trace.failCleanup = false;
      expect(await _snapshot(h.db), before);
      expect(
        await h.db
            .customSelect(
              "SELECT name FROM sqlite_temp_master WHERE name='chat_page_missing_ids'",
            )
            .get(),
        isEmpty,
      );
      await h.cache.storeHistoryPage(
        'chat',
        const [],
        ownerUserId: 'owner',
        boundary: all[60],
        older: true,
      );
      expect(
        await h.cache.readMessage(all[118].id, currentUserId: 'owner'),
        isNull,
      );
    },
  );

  test(
    'concurrent pages serialize their temporary ID sets and publish only commits',
    () async {
      final h = _Harness();
      addTearDown(h.db.close);
      final a = _messages(600);
      final b = [for (final m in a) m.copyWith(id: 'b${m.id}', chatId: 'b')];
      await h.cache.upsertMessages([...a, ...b]);
      final emissions = <List<ChatMessage>>[];
      final committed = Completer<void>();
      final subscription = h.cache
          .watchMessages('chat', currentUserId: 'owner')
          .listen((rows) {
            emissions.add(rows);
            if (rows.length == 62 && !committed.isCompleted) {
              committed.complete();
            }
          });
      await Future<void>.delayed(Duration.zero);
      await Future.wait([
        h.cache.storeHistoryPage(
          'chat',
          [a[70]],
          ownerUserId: 'owner',
          boundary: a[60],
          older: true,
        ),
        h.cache.storeHistoryPage(
          'b',
          [b[70]],
          ownerUserId: 'owner',
          boundary: b[60],
          older: true,
        ),
      ]);
      await committed.future.timeout(const Duration(seconds: 2));
      await subscription.cancel();
      expect(
        (await h.cache.watchMessages('chat', currentUserId: 'owner').first)
            .length,
        62,
      );
      expect(
        (await h.cache.watchMessages('b', currentUserId: 'owner').first).length,
        62,
      );
      expect(
        emissions.every((rows) => rows.length == 600 || rows.length == 62),
        isTrue,
      );
      expect(
        await h.db
            .customSelect(
              "SELECT name FROM sqlite_temp_master WHERE name='chat_page_missing_ids'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'temporary cleanup works through a background SQLite connection and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'history-page-isolate-',
      );
      final file = File('${directory.path}/cache.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
      try {
        final cache = ChatCacheDataSource(
          database: db,
          userIdProvider: () => 'owner',
        );
        final all = _messages(600);
        await cache.upsertMessages(all);
        await cache.storeHistoryPage(
          'chat',
          [all[70]],
          ownerUserId: 'owner',
          boundary: all[60],
          older: true,
        );
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
        final restored = ChatCacheDataSource(
          database: db,
          userIdProvider: () => 'owner',
        );
        expect(
          (await restored.watchMessages('chat', currentUserId: 'owner').first)
              .length,
          62,
        );
        expect(
          (await db.select(db.cachedChatHistoryRanges).get())
              .single
              .reachesStart,
          isTrue,
        );
        expect(
          await db
              .customSelect(
                "SELECT name FROM sqlite_temp_master WHERE name='chat_page_missing_ids'",
              )
              .get(),
          isEmpty,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'all 60 returned rows tombstoned do not resurrect or mark history ended',
    () async {
      final h = _Harness();
      addTearDown(h.db.close);
      final all = _messages(120);
      await h.cache.upsertMessages(all);
      final page = all.sublist(60);
      await h.cache.removeMessages('chat', page.map((m) => m.id).toSet());
      await h.cache.storeHistoryPage(
        'chat',
        page,
        ownerUserId: 'owner',
        boundary: all[59],
        older: true,
      );
      expect(
        (await h.db.select(h.db.cachedChatHistoryRanges).get())
            .single
            .reachesStart,
        isFalse,
      );
      expect(
        await h.cache.readMessage(page.first.id, currentUserId: 'owner'),
        isNull,
      );
      expect(
        await h.cache.readReactionState(page.first.id, ownerUserId: 'owner'),
        const MessageReactionState(),
      );
    },
  );
}

class _Harness {
  _Harness([_Trace? trace]) {
    final native = NativeDatabase.memory();
    db = AppDatabase.forTesting(
      trace == null ? native : native.interceptWith(trace),
    );
    cache = ChatCacheDataSource(database: db, userIdProvider: () => 'owner');
  }
  late final AppDatabase db;
  late final ChatCacheDataSource cache;
}

List<ChatMessage> _messages(int count) => [
  for (var i = 0; i < count; i++)
    ChatMessage(
      id: 'm${i.toString().padLeft(5, '0')}',
      chatId: 'chat',
      senderId: 'peer',
      text: 'message $i',
      isMine: false,
      timestamp: DateTime.utc(
        2026,
        10,
        18,
      ).subtract(Duration(microseconds: i ~/ 4)),
      type: MessageType.values[i % 4],
      mediaStoragePaths: i % 4 == 1 ? ['chat/$i.jpg'] : const [],
      mediaUrls: i % 4 == 1 ? ['file:///cache/$i.jpg'] : const [],
      audioStoragePath: i % 4 == 3 ? 'chat/$i.m4a' : null,
      audioUrl: i % 4 == 3 ? 'file:///cache/$i.m4a' : null,
      audioDuration: i % 4 == 3 ? const Duration(seconds: 4) : null,
      audioWaveform: i % 4 == 3 ? const [0.1, 0.8] : const [],
      latitude: i % 4 == 2 ? 55.75 : null,
      longitude: i % 4 == 2 ? 37.61 : null,
      reactionState: const MessageReactionState(
        version: 5,
        reactions: [
          MessageReaction(userId: 'peer', code: ReactionCode.fire, position: 4),
        ],
      ),
    ),
]..sort((a, b) => ChatHistoryCursor.of(b).compareTo(ChatHistoryCursor.of(a)));

MessageReply _reply(ChatMessage m) => MessageReply(
  messageId: m.id,
  senderId: m.senderId,
  isMine: false,
  type: m.type,
  text: m.text,
);

ChatMessage _remote(ChatMessage m) => ChatMessage(
  id: m.id,
  chatId: m.chatId,
  senderId: m.senderId,
  text: m.text,
  timestamp: m.timestamp,
  isMine: m.isMine,
  type: m.type,
  mediaStoragePaths: m.mediaStoragePaths,
  audioStoragePath: m.audioStoragePath,
  audioDuration: m.audioDuration,
  audioWaveform: m.audioWaveform,
  latitude: m.latitude,
  longitude: m.longitude,
  replyTo: m.replyTo,
  reactionState: const MessageReactionState(version: 2),
);

Future<void> _seedRich(_Harness h, List<ChatMessage> all, int variation) async {
  final local = [
    for (var i = 0; i < all.length; i++)
      if (i % 13 != variation)
        all[i].copyWith(replyTo: i % 7 == 0 ? _reply(all.last) : null),
  ];
  await h.cache.upsertMessages(local);
  await h.cache.upsertMessages(all, ownerUserId: 'other');
  await h.cache.upsertMessage(
    all.first.copyWith(
      id: 'foreign',
      chatId: 'elsewhere',
      replyTo: _reply(all.last),
    ),
  );
  for (var i = 0; i < all.length; i += 17) {
    await h.cache.upsertMessage(
      all[i].copyWith(status: MessageStatus.error, replyTo: _reply(all.last)),
      isPending: true,
    );
  }
  for (final m in [all[80], all.last]) {
    await h.cache.enqueueReaction(
      ownerUserId: 'owner',
      chatId: 'chat',
      messageId: m.id,
      operationId: m.id,
      code: ReactionCode.heart,
      expectedRevision: 3,
      dueAt: DateTime.utc(2026),
    );
  }
  await h.cache.putPendingOperation(
    PendingMessageOperation(
      id: 'outbox',
      chatId: 'chat',
      type: 'send',
      payload: const {'audio_path': '/cache/voice.m4a'},
      createdAt: DateTime.utc(2026),
    ),
  );
}

Future<Map<String, Object?>> _snapshot(AppDatabase db) async {
  final result = <String, Object?>{};
  for (final table in [
    'cached_messages',
    'cached_message_reaction_states',
    'pending_message_reactions',
    'pending_chat_operations',
    'cached_chat_history_ranges',
  ]) {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    final normalized = [
      for (final r in rows)
        Map<String, Object?>.of(r.data)..remove('cached_at'),
    ];
    normalized.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    result[table] = normalized;
  }
  return result;
}

class _Trace extends QueryInterceptor {
  bool enabled = false;
  bool failCoverage = false;
  bool failCleanup = false;
  final statements = <({String sql, List<Object?> args})>[];
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled) statements.add((sql: statement, args: List.of(args)));
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failCoverage &&
        statement.contains('INTO "cached_chat_history_ranges"')) {
      throw StateError('Injected coverage failure');
    }
    if (enabled) statements.add((sql: statement, args: List.of(args)));
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled) statements.add((sql: statement, args: List.of(args)));
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failCleanup && statement.contains('"cached_message_reaction_states"')) {
      throw StateError('Injected cleanup failure');
    }
    if (enabled) statements.add((sql: statement, args: List.of(args)));
    return executor.runDelete(statement, args);
  }
}
