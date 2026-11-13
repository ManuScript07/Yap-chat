// Opt-in benchmark: CHAT_HISTORY_BENCHMARK=1 flutter test <this file>.
// File-backed SQLite, production cache methods; no Supabase/network access.
import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';

void main() {
  test(
    'file-backed cache scaling, live updates and schema-25 migration',
    () async {
      final results = <Map<String, Object?>>[];
      final heap = await _HeapProbe.connect();
      AppDatabase? activeDatabase;
      final directory = await Directory.systemTemp.createTemp(
        'yap-chat-history-bench-',
      );
      try {
        for (final size in [1000, 10000, 100000]) {
          final file = File('${directory.path}/cache-$size.sqlite');
          final sqlTrace = _StatementTrace();
          final native = NativeDatabase(file);
          var db = activeDatabase = AppDatabase.forTesting(
            Platform.environment['CHAT_HISTORY_SQL_TRACE'] == '1'
                ? native.interceptWith(sqlTrace)
                : native,
          );
          var cache = ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          await db.customSelect('SELECT 1').get();
          final seed = Stopwatch()..start();
          await db.transaction(() async {
            for (var start = 0; start < size; start += 1000) {
              await db.batch(
                (batch) => batch.insertAll(db.cachedMessages, [
                  for (var i = start; i < start + 1000 && i < size; i++)
                    CachedMessagesCompanion.insert(
                      ownerUserId: 'owner',
                      id: _message(i).id,
                      chatId: 'chat',
                      senderId: 'peer',
                      messageText: _message(i).text,
                      timestamp: _message(i).timestamp,
                      timestampMicros: Value(
                        _message(i).timestamp.microsecondsSinceEpoch,
                      ),
                      hasExactTimestamp: const Value(true),
                      status: 'sent',
                      type: 'text',
                      mediaUrlsJson: '[]',
                      mediaStoragePathsJson: '[]',
                      audioWaveformJson: '[]',
                      isPending: false,
                      cachedAt: DateTime(2026),
                    ),
                ]),
              );
            }
          });
          seed.stop();
          // Establish one proven full-history interval without mapping it into Dart.
          await db
              .into(db.cachedChatHistoryRanges)
              .insert(
                CachedChatHistoryRangesCompanion.insert(
                  ownerUserId: 'owner',
                  chatId: 'chat',
                  oldestMicros: _message(
                    size - 1,
                  ).timestamp.microsecondsSinceEpoch,
                  oldestId: _message(size - 1).id,
                  newestMicros: _message(0).timestamp.microsecondsSinceEpoch,
                  newestId: _message(0).id,
                  reachesStart: true,
                ),
              );
          final head = [for (var i = 0; i < 60; i++) _message(i)];
          await cache.replaceRecentMessages('chat', head);
          final metrics = <String, Object?>{};
          final baselineHeap = await heap?.snapshot();
          final retainedHead = await cache
              .watchMessages('chat', currentUserId: 'owner', limit: 60)
              .first;
          final boundedHeap = await heap?.snapshot();
          final retainedFull = await cache
              .watchMessages('chat', currentUserId: 'owner')
              .first;
          final fullHeap = await heap?.snapshot();
          expect(retainedHead.length, 60);
          expect(retainedFull.length, size);
          metrics['heap_bytes'] = {
            'baseline': baselineHeap,
            'with_head_60': boundedHeap,
            'with_head_and_legacy_full': fullHeap,
            'note': 'VM heap after forced GC; not process RSS or GPU memory',
          };
          Future<void> measure(
            String label,
            Future<void> Function() run, {
            int samples = 20,
          }) async {
            await run(); // Warm-up reported separately from reopen below.
            final times = <double>[];
            for (var i = 0; i < samples; i++) {
              final timer = Stopwatch()..start();
              await run();
              times.add(timer.elapsedMicroseconds / 1000);
            }
            times.sort();
            metrics[label] = {
              'samples': samples,
              'p50_ms': times[(samples * .5).ceil() - 1],
              'p95_ms': times[(samples * .95).ceil() - 1],
              'max_ms': times.last,
            };
          }

          await measure('head_60', () async {
            expect(
              await cache
                  .watchMessages('chat', currentUserId: 'owner', limit: 60)
                  .first,
              hasLength(60),
            );
          });
          await measure('legacy_full_history', () async {
            expect(
              await cache.watchMessages('chat', currentUserId: 'owner').first,
              hasLength(size),
            );
          }, samples: 5);
          await measure('deep_older_60', () async {
            expect(
              await cache.readHistoryPage(
                'chat',
                _message(size - 100),
                ownerUserId: 'owner',
                older: true,
              ),
              hasLength(60),
            );
          });
          await measure('deep_newer_60', () async {
            expect(
              await cache.readHistoryPage(
                'chat',
                _message(size - 100),
                ownerUserId: 'owner',
                older: false,
              ),
              hasLength(60),
            );
          });
          await measure('reply_window_60', () async {
            expect(
              await cache.readHistoryWindow(
                'chat',
                _message(size ~/ 2).id,
                ownerUserId: 'owner',
              ),
              hasLength(60),
            );
          });
          await measure('unchanged_head_sync', () async {
            expect(await cache.replaceRecentMessages('chat', head), isFalse);
          });
          await measure('history_page_refresh_60', () async {
            await cache.storeHistoryPage(
              'chat',
              [for (var i = 101; i <= 160; i++) _message(i)],
              ownerUserId: 'owner',
              boundary: _message(100),
              older: true,
            );
          });
          if (Platform.environment['CHAT_HISTORY_SQL_TRACE'] == '1') {
            // Diagnostic only: profile production SQL against disposable data.
            // Keep it separate from the normal end-to-end timing above.
            sqlTrace.enabled = true;
            try {
              for (var sample = 0; sample < 5; sample++) {
                await cache.storeHistoryPage(
                  'chat',
                  [for (var i = 101; i <= 160; i++) _message(i)],
                  ownerUserId: 'owner',
                  boundary: _message(100),
                  older: true,
                );
              }
            } finally {
              sqlTrace.enabled = false;
            }
            final statements = sqlTrace.statements.entries.toList()
              ..sort((a, b) => b.value.micros.compareTo(a.value.micros));
            metrics['history_page_sql_trace'] = [
              for (final entry in statements)
                {
                  'sql': entry.key,
                  'calls': entry.value.calls,
                  'total_ms': entry.value.micros / 1000,
                  'plan': await db.executor.runSelect(
                    'EXPLAIN QUERY PLAN ${entry.key}',
                    entry.value.args,
                  ),
                },
            ];
            final ids = [for (var i = 101; i <= 160; i++) _message(i).id];
            final placeholders = List.filled(ids.length, '?').join(',');
            final cursor = _message(100);
            final edge = _message(160);
            final rangeArgs = <Object?>[
              'owner',
              'chat',
              cursor.timestamp.microsecondsSinceEpoch,
              cursor.id,
              edge.timestamp.microsecondsSinceEpoch,
              edge.id,
              ...ids,
            ];
            metrics['diagnostic_queries'] = {
              for (final direct in [false, true])
                'missing_ids_direct_bounds_$direct': await _profileQuery(
                  db.executor,
                  '''SELECT id FROM cached_messages
                  WHERE owner_user_id=? AND chat_id=? AND NOT is_pending
                    AND (timestamp_micros,id)<(?,?)
                    AND ${direct ? '(timestamp_micros,id)>=(?,?)' : 'NOT ((timestamp_micros,id)<(?,?))'}
                    AND id NOT IN ($placeholders)''',
                  rangeArgs,
                  expectedRows: 0,
                ),
              for (final withChat in [true, false])
                'read_ids_chat_predicate_$withChat': await _profileQuery(
                  db.executor,
                  '''SELECT * FROM cached_messages
                  WHERE owner_user_id=? ${withChat ? 'AND chat_id=?' : ''}
                    AND id IN ($placeholders)''',
                  ['owner', if (withChat) 'chat', ...ids],
                  expectedRows: ids.length,
                ),
            };
          }
          // Diagnostic index exists only in this disposable benchmark file.
          // This is NOT an application schema change.
          if (size == 100000) {
            await db.customStatement(
              'CREATE INDEX benchmark_reply_lookup ON cached_messages(owner_user_id,chat_id,reply_message_id)',
            );
            await measure(
              'history_page_refresh_with_diagnostic_reply_index',
              () async {
                await cache.storeHistoryPage(
                  'chat',
                  [for (var i = 101; i <= 160; i++) _message(i)],
                  ownerUserId: 'owner',
                  boundary: _message(100),
                  older: true,
                );
              },
            );
            await db.customStatement('DROP INDEX benchmark_reply_lookup');
          }
          final plans = <String, Object?>{};
          for (final older in [true, false]) {
            final sign = older ? '<' : '>';
            final order = older ? 'DESC' : 'ASC';
            final plan = await db.customSelect(
              '''EXPLAIN QUERY PLAN SELECT * FROM cached_messages
            WHERE owner_user_id='owner' AND chat_id='chat'
            AND (timestamp_micros,id) $sign (${_message(size - 100).timestamp.microsecondsSinceEpoch},'${_message(size - 100).id}')
            ORDER BY timestamp_micros $order,id $order LIMIT 60''',
            ).get();
            final details = plan.map((r) => r.read<String>('detail')).join(' ');
            expect(details, contains('cached_messages_owner_chat_cursor_idx'));
            expect(details, isNot(contains('TEMP B-TREE')));
            plans[older ? 'older' : 'newer'] = details;
          }
          await db.close();
          final reopen = Stopwatch()..start();
          db = activeDatabase = AppDatabase.forTesting(NativeDatabase(file));
          cache = ChatCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          expect(
            await cache
                .watchMessages('chat', currentUserId: 'owner', limit: 60)
                .first,
            hasLength(60),
          );
          final reopenMs = reopen.elapsedMicroseconds / 1000;
          // Reconstruct the old columns, then execute the REAL upgrade method.
          await db.customStatement(
            'DROP INDEX cached_messages_owner_chat_cursor_idx',
          );
          await db.customStatement(
            'ALTER TABLE cached_messages DROP COLUMN timestamp_micros',
          );
          await db.customStatement(
            'ALTER TABLE cached_messages DROP COLUMN has_exact_timestamp',
          );
          await db.customStatement('DROP TABLE cached_chat_history_ranges');
          await db.customStatement('PRAGMA user_version=25');
          await db.close();
          final migration = Stopwatch()..start();
          db = activeDatabase = AppDatabase.forTesting(NativeDatabase(file));
          await db.customSelect('SELECT 1').get();
          final migrationMs = migration.elapsedMicroseconds / 1000;
          expect(
            (await db
                    .customSelect('SELECT count(*) AS n FROM cached_messages')
                    .getSingle())
                .read<int>('n'),
            size,
          );
          expect(
            (await db
                    .customSelect(
                      'SELECT count(*) AS n FROM cached_messages WHERE has_exact_timestamp=1',
                    )
                    .getSingle())
                .read<int>('n'),
            0,
          );
          await db.close();
          activeDatabase = null;
          final row = <String, Object?>{
            'size': size,
            'seed_ms': seed.elapsedMilliseconds,
            'metrics': metrics,
            'reopen_to_head_ms': reopenMs,
            'migration_25_to_26_ms': migrationMs,
            'sqlite_bytes': await file.length(),
            'plans': plans,
          };
          results.add(row);
          // ignore: avoid_print
          print('SQLITE_BENCHMARK ${jsonEncode(row)}');
        }
        final out = File(
          '.dart_tool/chat_history_validation/'
          '${Platform.environment['CHAT_HISTORY_SQLITE_RESULT'] ?? 'sqlite.json'}',
        );
        await out.parent.create(recursive: true);
        await out.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'runtime': Platform.version,
            'os': Platform.operatingSystem,
            'mode':
                'flutter test desktop/JIT; warm file-backed SQLite; OS cache not flushed',
            'results': results,
          }),
        );
      } finally {
        await heap?.close();
        await activeDatabase?.close();
        // Only this exact freshly-created temporary benchmark directory.
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['CHAT_HISTORY_BENCHMARK'] == '1'
        ? false
        : 'Opt-in performance test',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ChatMessage _message(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(8, '0')}',
  chatId: 'chat',
  senderId: 'peer',
  text: '${'synthetic text ' * 12}$index',
  timestamp: DateTime.utc(
    2026,
    10,
    18,
  ).subtract(Duration(microseconds: index * 1001)).toLocal(),
  isMine: false,
);

/// Installed only in this opt-in benchmark, never in application connections.
class _StatementTrace extends QueryInterceptor {
  bool enabled = false;
  final statements = <String, ({int calls, int micros, List<Object?> args})>{};

  Future<T> _measure<T>(
    String sql,
    List<Object?> args,
    Future<T> Function() run,
  ) async {
    if (!enabled) return run();
    final timer = Stopwatch()..start();
    try {
      return await run();
    } finally {
      final previous = statements[sql];
      statements[sql] = (
        calls: (previous?.calls ?? 0) + 1,
        micros: (previous?.micros ?? 0) + timer.elapsedMicroseconds,
        args: previous?.args ?? List<Object?>.of(args),
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _measure(statement, args, () => executor.runSelect(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _measure(statement, args, () => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _measure(statement, args, () => executor.runDelete(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _measure(statement, args, () => executor.runInsert(statement, args));
}

Future<Map<String, Object?>> _profileQuery(
  QueryExecutor executor,
  String sql,
  List<Object?> args, {
  required int expectedRows,
}) async {
  final plan = await executor.runSelect('EXPLAIN QUERY PLAN $sql', args);
  expect(await executor.runSelect(sql, args), hasLength(expectedRows));
  final times = <double>[];
  for (var sample = 0; sample < 20; sample++) {
    final timer = Stopwatch()..start();
    final rows = await executor.runSelect(sql, args);
    times.add(timer.elapsedMicroseconds / 1000);
    expect(rows, hasLength(expectedRows));
  }
  times.sort();
  return {'p50_ms': times[9], 'p95_ms': times[18], 'plan': plan};
}

class _HeapProbe {
  _HeapProbe(this.socket, this.isolateId) {
    socket.listen((data) {
      final response = jsonDecode(data as String) as Map<String, dynamic>;
      pending.remove(response['id'])?.complete(response);
    });
  }
  final WebSocket socket;
  final String isolateId;
  final pending = <String, Completer<Map<String, dynamic>>>{};
  int sequence = 0;
  static Future<_HeapProbe?> connect() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverWebSocketUri;
    final id = developer.Service.getIsolateId(Isolate.current);
    if (uri == null || id == null) return null;
    return _HeapProbe(await WebSocket.connect(uri.toString()), id);
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic> extra = const {},
  ]) {
    final id = '${++sequence}';
    final result = Completer<Map<String, dynamic>>();
    pending[id] = result;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': {'isolateId': isolateId, ...extra},
      }),
    );
    return result.future.timeout(const Duration(seconds: 10));
  }

  Future<int?> snapshot() async {
    await request('getAllocationProfile', {'gc': true});
    final response = await request('getMemoryUsage');
    return (response['result'] as Map?)?['heapUsage'] as int?;
  }

  Future<void> close() => socket.close();
}
