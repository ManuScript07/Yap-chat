import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

import '../repositories/chat/support/support.dart';

void main() {
  test(
    'real deletion costs, old and new algorithms on identical file-backed data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yap-page-cleanup-',
      );
      final results = <Map<String, Object?>>[];
      try {
        for (final size in [1000, 10000, 100000]) {
          final db = AppDatabase.forTesting(
            NativeDatabase(File('${directory.path}/$size.sqlite')),
          );
          final cache = ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          try {
            await db.transaction(() async {
              for (var start = 0; start < size; start += 1000) {
                await db.batch(
                  (batch) => batch.insertAll(db.cachedMessages, [
                    for (var i = start; i < start + 1000 && i < size; i++)
                      CachedMessagesCompanion.insert(
                        ownerUserId: 'owner',
                        id: _m(i).id,
                        chatId: 'chat',
                        senderId: 'peer',
                        messageText: '$i',
                        timestamp: _m(i).timestamp,
                        timestampMicros: Value(
                          _m(i).timestamp.microsecondsSinceEpoch,
                        ),
                        hasExactTimestamp: const Value(true),
                        status: 'sent',
                        type: 'text',
                        mediaUrlsJson: '[]',
                        mediaStoragePathsJson: '[]',
                        audioWaveformJson: '[]',
                        replyMessageId: i % 1000 == 0
                            ? Value(_m(110).id)
                            : const Value.absent(),
                        replySenderId: i % 1000 == 0
                            ? const Value('peer')
                            : const Value.absent(),
                        replyType: i % 1000 == 0
                            ? const Value('text')
                            : const Value.absent(),
                        replyText: i % 1000 == 0
                            ? const Value('110')
                            : const Value.absent(),
                        isPending: false,
                        cachedAt: DateTime.utc(2026),
                      ),
                  ]),
                );
              }
            });
            for (final scenario in ['unchanged', 'one_missing', 'empty_tail']) {
              final page = scenario == 'empty_tail'
                  ? <ChatMessage>[]
                  : [
                      for (
                        var i = 101;
                        i <= (scenario == 'one_missing' ? 161 : 160);
                        i++
                      )
                        if (scenario != 'one_missing' || i != 110) _m(i),
                    ];
              for (final indexed in [false, true]) {
                if (indexed) {
                  // Diagnostic-only, not yet an application index.
                  await db.customStatement(
                    'CREATE INDEX benchmark_page_reply_idx ON cached_messages(owner_user_id,chat_id,reply_message_id) WHERE reply_message_id IS NOT NULL',
                  );
                }
                for (final legacy in [true, false]) {
                  final times = <double>[];
                  for (var sample = 0; sample < 9; sample++) {
                    try {
                      await db.transaction(() async {
                        final timer = Stopwatch()..start();
                        if (legacy) {
                          await storeHistoryPageReference(
                            db,
                            cache,
                            'chat',
                            page,
                            ownerUserId: 'owner',
                            boundary: _m(100),
                            older: true,
                          );
                        } else {
                          await cache.storeHistoryPage(
                            'chat',
                            page,
                            ownerUserId: 'owner',
                            boundary: _m(100),
                            older: true,
                          );
                        }
                        if (sample > 0) {
                          times.add(timer.elapsedMicroseconds / 1000);
                        }
                        final count =
                            (await db
                                    .customSelect(
                                      'SELECT count(*) n FROM cached_messages',
                                    )
                                    .getSingle())
                                .read<int>('n');
                        expect(
                          count,
                          scenario == 'empty_tail'
                              ? 101
                              : size - (scenario == 'one_missing' ? 1 : 0),
                        );
                        throw const _Rollback();
                      });
                    } on _Rollback {
                      // Restore exactly the same fixture before the next sample.
                    }
                  }
                  times.sort();
                  results.add({
                    'size': size,
                    'scenario': scenario,
                    'legacy': legacy,
                    'reply_index': indexed,
                    'p50_ms': times[(times.length * .5).ceil() - 1],
                    'max_ms': times.last,
                  });
                }
                if (indexed) {
                  await db.customStatement(
                    'DROP INDEX benchmark_page_reply_idx',
                  );
                }
              }
            }
          } finally {
            await db.close();
          }
        }
        final out = File(
          '.dart_tool/chat_history_validation/sqlite_page_cleanup.json',
        );
        await out.parent.create(recursive: true);
        await out.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'runtime': Platform.version,
            'mode':
                'warm desktop/JIT, file-backed; rollback outside measured operation; 8 measured samples',
            'results': results,
          }),
        );
        // ignore: avoid_print
        print('PAGE_CLEANUP_BENCHMARK ${jsonEncode(results)}');
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['CHAT_HISTORY_BENCHMARK'] == '1'
        ? false
        : 'Opt-in performance test',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class _Rollback implements Exception {
  const _Rollback();
}

ChatMessage _m(int i) => ChatMessage(
  id: 'm${i.toString().padLeft(8, '0')}',
  chatId: 'chat',
  senderId: 'peer',
  text: '$i',
  timestamp: DateTime.utc(
    2026,
    10,
    18,
  ).subtract(Duration(microseconds: i * 1001)),
  isMine: false,
);
