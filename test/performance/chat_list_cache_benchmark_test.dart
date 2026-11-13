// File-backed, opt-in. Production cache methods; never a network request.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

final _base = DateTime.utc(2026);
String _id(int n) => n.toString().padLeft(9, '0');
DateTime _activity(int n) => _base.add(Duration(microseconds: n));
Chat _chat(int n, {String? text}) => Chat(
  id: _id(n),
  peerId: 'peer-$n',
  userName: 'Чат $n',
  lastMessage: text ?? 'text $n',
  lastMessageTime: _base.add(Duration(seconds: n)),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);

void main() {
  test(
    'bounded cache read/write scaling on file-backed SQLite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yap-chat-list-cache-',
      );
      final root = await directory.resolveSymbolicLinks();
      final results = <Map<String, Object?>>[];
      AppDatabase? active;
      try {
        for (final size in [1000, 10000, 100000]) {
          final trace = _Trace();
          final file = File('${directory.path}/$size.sqlite');
          var db = active = AppDatabase.forTesting(
            NativeDatabase(file).interceptWith(trace),
          );
          var cache = ChatsCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          await db.transaction(() async {
            for (var start = 0; start < size; start += 1000) {
              await db.batch(
                (b) => b.insertAll(db.cachedChats, [
                  for (var i = start; i < start + 1000 && i < size; i++)
                    CachedChatsCompanion.insert(
                      ownerUserId: 'owner',
                      id: _id(i),
                      peerId: 'peer-$i',
                      peerUsername: 'u$i',
                      peerDisplayName: i == size - 1
                          ? 'Редкий пользователь'
                          : 'Чат $i',
                      peerDisplayNameSearch: Value(
                        i == size - 1 ? 'редкий пользователь' : 'чат $i',
                      ),
                      lastMessage: 'text $i',
                      lastMessageType: 'text',
                      lastMessageTime: _base.add(Duration(seconds: i)),
                      unreadCount: 1,
                      isLastMessageFromMe: false,
                      isMuted: false,
                      cachedAt: _base,
                    ),
                ]),
              );
            }
          });
          final timings = <String, Object?>{};
          Future<Map<String, Object?>> measure(
            Future<void> Function() body,
          ) async {
            final samples = <double>[];
            var maxRows = 0;
            var maxSelects = 0;
            for (var i = 0; i < 9; i++) {
              trace.reset();
              trace.enabled = true;
              final timer = Stopwatch()..start();
              await body();
              timer.stop();
              trace.enabled = false;
              if (i >= 2) samples.add(timer.elapsedMicroseconds / 1000);
              if (trace.maxRows > maxRows) maxRows = trace.maxRows;
              if (trace.selects > maxSelects) maxSelects = trace.selects;
            }
            samples.sort();
            final diagnostics = <Map<String, Object?>>[];
            for (final record in trace.records) {
              final plan = await db.executor.runSelect(
                'EXPLAIN QUERY PLAN ${record['sql']}',
                record['args'] as List<Object?>,
              );
              if ((record['sql'] as String).contains('WITH requested(id)')) {
                expect(
                  plan.toString(),
                  contains(
                    (record['sql'] as String).contains(
                          'cached_chat_list_entries',
                        )
                        ? 'chat_id=?'
                        : 'id=?',
                  ),
                );
              }
              diagnostics.add({...record, 'plan': plan});
            }
            return {
              'median_ms': samples[samples.length ~/ 2],
              'max_ms': samples.last,
              'max_rows_per_select': maxRows,
              'max_selects': maxSelects,
              'statements': diagnostics,
            };
          }

          timings['legacy_head'] = await measure(() async {
            expect((await cache.readListSlice()).chats, hasLength(50));
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['legacy_search'] = await measure(() async {
            expect(
              (await cache.readListSlice(query: 'Редкий')).chats,
              hasLength(1),
            );
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['available_head'] = await measure(() async {
            expect((await cache.readAvailableSlice()).chats, hasLength(50));
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['available_deep'] = await measure(() async {
            expect(
              (await cache.readAvailableSlice(
                after: ChatListLocalCursor(
                  query: '',
                  activityMicros: _chat(
                    100,
                  ).lastMessageTime.microsecondsSinceEpoch,
                  chatId: _id(100),
                  serverBacked: false,
                ),
              )).chats,
              hasLength(50),
            );
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['available_selected_50'] = await measure(() async {
            expect(
              await cache.readAvailableItems({
                for (var i = 0; i < 50; i++) _id(i),
              }),
              hasLength(50),
            );
            expect(trace.maxRows, lessThanOrEqualTo(50));
          });
          final page = ChatListPage(
            items: [
              for (var i = size - 1; i >= size - 50; i--)
                ChatListPageItem(chat: _chat(i), activityAt: _activity(i)),
            ],
            query: '',
            unreadTotal: size,
            nextCursor: ChatListPageCursor(
              activityAt: _activity(size - 50),
              conversationId: _id(size - 50),
            ),
          );
          await cache.applyListPage(await cache.beginListRefresh(), page);
          // The retained tail simulates pages already visited in earlier sessions.
          // Direct fixture seeding is outside measured application operations.
          await db.transaction(() async {
            for (var start = 0; start < size - 50; start += 1000) {
              await db.batch(
                (b) => b.insertAll(db.cachedChatListEntries, [
                  for (var i = start; i < start + 1000 && i < size - 50; i++)
                    CachedChatListEntriesCompanion.insert(
                      ownerUserId: 'owner',
                      query: '',
                      chatId: _id(i),
                      activityMicros: _activity(i).microsecondsSinceEpoch,
                    ),
                ]),
              );
            }
          });
          timings['covered_head'] = await measure(() async {
            expect((await cache.readListSlice()).chats, hasLength(50));
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['covered_middle'] = await measure(() async {
            expect(
              (await cache.readListSlice(
                after: ChatListLocalCursor(
                  query: '',
                  activityMicros: _activity(size ~/ 2).microsecondsSinceEpoch,
                  chatId: _id(size ~/ 2),
                  serverBacked: true,
                ),
              )).chats,
              hasLength(50),
            );
            expect(trace.maxRows, lessThanOrEqualTo(51));
          });
          timings['head_unchanged'] = await measure(() async {
            final request = await cache.beginListRefresh();
            expect(await cache.applyListPage(request, page), true);
            expect(trace.maxRows, lessThanOrEqualTo(50));
          });
          var revision = 0;
          timings['head_changed'] = await measure(() async {
            revision++;
            final changed = ChatListPage(
              items: [
                for (var i = size - 1; i >= size - 50; i--)
                  ChatListPageItem(
                    chat: _chat(i, text: 'revision $revision'),
                    activityAt: _activity(i),
                  ),
              ],
              query: '',
              unreadTotal: size,
              nextCursor: page.nextCursor,
            );
            expect(
              await cache.applyListPage(
                await cache.beginListRefresh(),
                changed,
              ),
              true,
            );
            expect(trace.maxRows, lessThanOrEqualTo(50));
          });
          final plans = <Object?>[];
          final deltaIds = {
            for (var i = size ~/ 2; i < size ~/ 2 + 50; i++) _id(i),
          };
          List<Chat> delta = [];
          Map<String, DateTime> deltaActivity = {};
          timings['delta_metadata_only_50'] = await measure(() async {
            revision++;
            await cache.applySummaryBatch(deltaIds, [
              for (var i = size ~/ 2; i < size ~/ 2 + 50; i++)
                _chat(i, text: 'delta $revision'),
            ]);
          });
          timings['delta_positioned_50'] = await measure(() async {
            revision++;
            delta = [
              for (var i = size ~/ 2; i < size ~/ 2 + 50; i++)
                _chat(i, text: 'delta $revision'),
            ];
            deltaActivity = {
              for (var i = size ~/ 2; i < size ~/ 2 + 50; i++)
                _id(i): _activity(i + revision * size),
            };
            await cache.applySummaryBatch(
              deltaIds,
              delta,
              activityByChatId: deltaActivity,
            );
            expect(trace.maxRows, lessThanOrEqualTo(50));
          });
          timings['delta_identical_50'] = await measure(() async {
            await cache.applySummaryBatch(
              deltaIds,
              delta,
              activityByChatId: deltaActivity,
            );
          });
          for (final query in [
            'ч',
            'ча',
            'чат',
            'чат 5',
            'чат 50',
            'чат 500',
            'чат 5000',
            'чат 50000',
          ]) {
            await cache.applyListPage(
              await cache.beginListRefresh(query: query),
              ChatListPage(
                items: [],
                query: query,
                nextCursor: null,
                unreadTotal: size,
              ),
            );
          }
          timings['delta_positioned_50_all_searches'] = await measure(() async {
            revision++;
            delta = [
              for (var i = size ~/ 2; i < size ~/ 2 + 50; i++)
                _chat(i, text: 'delta $revision'),
            ];
            deltaActivity = {
              for (var i = size ~/ 2; i < size ~/ 2 + 50; i++)
                _id(i): _activity(i + revision * size),
            };
            await cache.applySummaryBatch(
              deltaIds,
              delta,
              activityByChatId: deltaActivity,
            );
            expect(trace.maxRows, lessThanOrEqualTo(50));
          });
          for (final after in [
            null,
            ChatListLocalCursor(
              query: '',
              activityMicros: _activity(size ~/ 2).microsecondsSinceEpoch,
              chatId: _id(size ~/ 2),
              serverBacked: true,
            ),
          ]) {
            trace.reset();
            trace.enabled = true;
            await cache.readListSlice(after: after);
            trace.enabled = false;
            final sql = trace.sliceSql;
            expect(sql, isNotEmpty);
            final plan = await db.executor.runSelect(
              'EXPLAIN QUERY PLAN $sql',
              trace.sliceArgs,
            );
            expect(plan.toString(), isNot(contains('TEMP B-TREE')));
            plans.add(plan);
          }
          await db.close();
          active = null;
          db = active = AppDatabase.forTesting(NativeDatabase(file));
          cache = ChatsCacheDataSource(
            database: db,
            userIdProvider: () => 'owner',
          );
          final reopen = Stopwatch()..start();
          final slice = await cache.readListSlice();
          reopen.stop();
          expect(slice.chats, hasLength(50));
          expect((await cache.readUnreadState()).total, size);
          await db.close();
          active = null;
          results.add({
            'chats': size,
            'timings': timings,
            'reopen_first_slice_ms': reopen.elapsedMicroseconds / 1000,
            'sqlite_bytes': await file.length(),
            'actual_slice_plans': plans,
          });
        }
        final out = Directory('.dart_tool/chat_list_cache_validation');
        await out.create(recursive: true);
        final outputName =
            const bool.fromEnvironment('CHAT_LIST_DELTA_BENCHMARK')
            ? 'sqlite_delta_benchmark.json'
            : 'sqlite_benchmark.json';
        await File('${out.path}/$outputName').writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'results': results, 'network_requests': 0}),
        );
        for (final row in results) {
          stdout.writeln('CHAT_LIST_CACHE_BENCH ${jsonEncode(row)}');
        }
      } finally {
        await active?.close();
        if (await directory.resolveSymbolicLinks() != root) {
          throw StateError('Temporary benchmark directory changed');
        }
        await Directory(root).delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('CHAT_LIST_CACHE_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _Trace extends QueryInterceptor {
  bool enabled = false;
  int maxRows = 0;
  int selects = 0;
  String sliceSql = '';
  List<Object?> sliceArgs = [];
  final records = <Map<String, Object?>>[];
  void reset() {
    maxRows = 0;
    selects = 0;
    sliceSql = '';
    sliceArgs = [];
    records.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) async {
    final timer = Stopwatch()..start();
    final rows = await executor.runSelect(sql, args);
    if (enabled) {
      selects++;
      records.add({
        'sql': sql,
        'args': List<Object?>.of(args),
        'micros': timer.elapsedMicroseconds,
      });
      if (rows.length > maxRows) maxRows = rows.length;
      if (sql.contains('AS order_micros')) {
        sliceSql = sql;
        sliceArgs = List.of(args);
      }
    }
    return rows;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) async {
    final timer = Stopwatch()..start();
    final result = await executor.runUpdate(sql, args);
    if (enabled && sql.trimLeft().startsWith('DELETE')) {
      records.add({
        'sql': sql,
        'args': List<Object?>.of(args),
        'micros': timer.elapsedMicroseconds,
      });
    }
    return result;
  }
}
