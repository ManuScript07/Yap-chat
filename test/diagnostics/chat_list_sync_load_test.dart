// Scaling probes against the production repository + real Drift.
// Backend is fake here: timings are host-side diagnostics, not phone/SQL latency.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

const enabled = bool.fromEnvironment('CHAT_LIST_LOAD_DIAGNOSTIC');
void main() {
  for (final count in [100, 1000]) {
    test(
      'list load: $count chats and 100 burst events share one watcher',
      () async {
        final h = await _Harness.create(count);
        final subscriptions = <StreamSubscription<List<Chat>>>[];
        addTearDown(() async {
          for (final sub in subscriptions) {
            await sub.cancel();
          }
          await h.dispose();
        });
        final loaded = Completer<void>();
        subscriptions.add(
          h.repository.watchChats().listen((chats) {
            if (chats.length == count && !loaded.isCompleted) loaded.complete();
          }),
        );
        await loaded.future.timeout(const Duration(seconds: 15));
        for (var i = 0; i < 4; i++) {
          subscriptions.add(h.repository.watchChats().listen((_) {}));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(h.remote.watchCalls, 1);
        final baseline = h.remote.fetchCalls;
        for (var i = 0; i < 100; i++) {
          h.remote.emit('$i');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(h.remote.fetchCalls - baseline, 0);
        expect(h.remote.partialCalls, 2);
        expect(h.remote.maximumConcurrent, 1);
        expect(h.messageRemote.fetchCalls, 0);
        _report({
          'scenario': 'burst',
          'chats': count,
          'events': 100,
          'summary_requests': h.remote.fetchCalls - baseline,
          'partial_summary_requests': h.remote.partialCalls,
          'watch_subscriptions': h.remote.watchCalls,
          'history_requests': h.messageRemote.fetchCalls,
          'max_concurrent_summary_requests': h.remote.maximumConcurrent,
          'local_preview_reads': h.messages.previewReads,
        });
      },
      skip: !enabled,
    );
  }

  test('list load: sustained events use bounded partial refreshes', () async {
    final h = await _Harness.create(100);
    final loaded = Completer<void>();
    final sub = h.repository.watchChats().listen((chats) {
      if (chats.length == 100 && !loaded.isCompleted) loaded.complete();
    });
    addTearDown(() async {
      await sub.cancel();
      await h.dispose();
    });
    await loaded.future.timeout(const Duration(seconds: 15));
    final before = h.remote.fetchCalls;
    for (var i = 0; i < 30; i++) {
      h.remote.emit('${i % 100}');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final requests = h.remote.fetchCalls - before;
    expect(requests, 0);
    expect(h.remote.partialCalls, inInclusiveRange(3, 5));
    expect(h.remote.maximumConcurrent, 1);
    expect(h.remote.watchCalls, 1);
    expect(h.messageRemote.fetchCalls, 0);
    _report({
      'scenario': 'sustained',
      'chats': 100,
      'events': 30,
      'event_period_ms': 100,
      'summary_requests': requests,
      'partial_summary_requests': h.remote.partialCalls,
      'max_concurrent_summary_requests': h.remote.maximumConcurrent,
      'history_requests': 0,
      'local_preview_reads': h.messages.previewReads,
    });
  }, skip: !enabled);

  test(
    'list load: idle watcher still refreshes after twenty seconds',
    () async {
      final h = await _Harness.create(100);
      final loaded = Completer<void>();
      final sub = h.repository.watchChats().listen((chats) {
        if (chats.length == 100 && !loaded.isCompleted) loaded.complete();
      });
      addTearDown(() async {
        await sub.cancel();
        await h.dispose();
      });
      await loaded.future.timeout(const Duration(seconds: 15));
      final before = h.remote.fetchCalls;
      await Future<void>.delayed(const Duration(seconds: 21));
      expect(h.remote.fetchCalls - before, 1);
      expect(h.remote.watchCalls, 1);
      _report({
        'scenario': 'idle',
        'chats': 100,
        'elapsed_seconds': 21,
        'summary_requests': h.remote.fetchCalls - before,
        'watch_subscriptions': 1,
      });
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('list cache: one changed chat upserts only that row', () async {
    final trace = _InsertTrace();
    final h = await _Harness.create(1000, trace: trace);
    addTearDown(h.dispose);
    await h.cache.replaceAll(h.remote.chats);
    trace.enabled = true;
    expect(await h.cache.replaceAll(h.remote.chats), false);
    expect(trace.inserts, 0);
    h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 2);
    final timer = Stopwatch()..start();
    expect(await h.cache.replaceAll(h.remote.chats), true);
    expect(trace.inserts, 1);
    expect(
      (await h.cache.read()).firstWhere((c) => c.id == '0').unreadCount,
      2,
    );
    _report({
      'scenario': 'single_chat_changed',
      'chats': 1000,
      'sqlite_chat_upserts': trace.inserts,
      'elapsed_ms': timer.elapsedMilliseconds,
    });
  }, skip: !enabled);

  test(
    'list cache: truncated snapshot prunes rows that still exist on server',
    () async {
      final h = await _Harness.create(1001);
      addTearDown(h.dispose);
      await h.cache.replaceAll(h.remote.chats);
      expect(await h.cache.read(), hasLength(1001));
      final ms = Stopwatch()..start();
      await h.cache.replaceAll(h.remote.chats.take(1000).toList());
      expect(await h.cache.read(), hasLength(1000));
      _report({
        'scenario': 'truncated_cache_snapshot',
        'before': 1001,
        'after': 1000,
        'elapsed_ms': ms.elapsedMilliseconds,
      });
    },
    skip: !enabled,
  );
}

void _report(Map<String, Object> data) {
  final value = jsonEncode(data);
  File(
    'tmp/chat_list_sync_diagnostic.jsonl',
  ).writeAsStringSync('$value\n', mode: FileMode.append);
  // ignore: avoid_print
  print('CHAT_LIST_DIAGNOSTIC $value');
}

class _Harness {
  _Harness(
    this.repository,
    this.remote,
    this.messageRemote,
    this.messages,
    this.cache,
    this.database,
    this.media,
  );
  final ChatsRepository repository;
  final _Remote remote;
  final _MessageRemote messageRemote;
  final _Messages messages;
  final ChatsCacheDataSource cache;
  final AppDatabase database;
  final MediaCacheService media;
  static Future<_Harness> create(int count, {_InsertTrace? trace}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final native = NativeDatabase.memory();
    final db = AppDatabase.forTesting(
      trace == null ? native : native.interceptWith(trace),
    );
    final account = AccountSessionController(initialUserId: 'owner');
    final media = MediaCacheService(database: db);
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: prefs,
      talker: Talker(),
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => 'owner',
    );
    final messages = _Messages(db);
    final remote = _Remote([
      for (var i = 0; i < count; i++)
        Chat(
          id: '$i',
          peerId: 'peer-$i',
          userName: 'Peer $i',
          lastMessageId: 'message-$i',
          lastMessage: 'preview',
          lastMessageTime: DateTime(2026),
          unreadCount: 1,
          isOnline: false,
          isLastMessageFromMe: false,
        ),
    ]);
    final messageRemote = _MessageRemote();
    final sync = ConversationSyncService(
      cache: messages,
      remote: messageRemote,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: messageRemote,
        mediaCache: media,
      ),
      chatsCache: cache,
      accountSessionController: account,
    );
    return _Harness(
      ChatsRepository(
        config: config,
        cache: cache,
        remote: remote,
        mediaCache: media,
        chatCache: messages,
        conversationSync: sync,
        accountSessionController: account,
      ),
      remote,
      messageRemote,
      messages,
      cache,
      db,
      media,
    );
  }

  Future<void> dispose() async {
    await remote.changes.close();
    media.dispose();
    await database.close();
  }
}

class _InsertTrace extends QueryInterceptor {
  bool enabled = false;
  int inserts = 0;
  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled && statement.contains('cached_chats')) inserts++;
    return executor.runInsert(statement, args);
  }
}

class _Remote extends ChatsRemoteDataSource {
  _Remote(this.chats)
    : super(
        client: SupabaseClient('http://localhost', 'diagnostic-key'),
        talker: Talker(),
      );
  final List<Chat> chats;
  final changes = StreamController<ConversationChange>.broadcast();
  int fetchCalls = 0, watchCalls = 0, concurrent = 0, maximumConcurrent = 0;
  int partialCalls = 0;
  @override
  Stream<ConversationChange> watchChanges() {
    watchCalls++;
    return changes.stream;
  }

  void emit(String id) =>
      changes.add(ConversationChange(conversationId: id, reason: 'insert'));
  @override
  Future<List<Chat>> fetchChats() async {
    fetchCalls++;
    return _fetch(chats);
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    partialCalls++;
    return _fetch(chats.where((c) => ids.contains(c.id)).toList());
  }

  Future<List<Chat>> _fetch(List<Chat> result) async {
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return result;
    } finally {
      concurrent--;
    }
  }
}

class _Messages extends ChatCacheDataSource {
  _Messages(AppDatabase db)
    : super(database: db, userIdProvider: () => 'owner');
  int previewReads = 0;
  @override
  Future<ChatMessage?> readLatestMessage(
    String chatId, {
    required String currentUserId,
  }) {
    previewReads++;
    return super.readLatestMessage(chatId, currentUserId: currentUserId);
  }
}

class _MessageRemote extends ChatRemoteDataSource {
  _MessageRemote()
    : super(client: SupabaseClient('http://localhost', 'diagnostic-key'));
  int fetchCalls = 0;
  @override
  String get currentUserId => 'owner';
  @override
  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    fetchCalls++;
    return const [];
  }
}
