import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  for (final count in [0, 1, 49, 50]) {
    test(
      'bulk actions accept $count selected chats in a single batch',
      () async {
        final h = await _Harness.create();
        final ids = {for (var i = 0; i < count; i++) '$i'};
        await h.cache.replaceAll([for (final id in ids) _chat(id, false)]);
        await h.repository.markAsRead(ids);
        expect(h.remote.readCalls, count == 0 ? 0 : 1);
        expect(
          (await h.cache.read()).map((chat) => chat.unreadCount),
          everyElement(0),
        );
        await h.repository.setMuted(ids, isMuted: true);
        expect(h.remote.calls.length, count == 0 ? 0 : 1);
        await h.repository.deleteChats(ids);
        expect(h.remote.hideCalls, count == 0 ? 0 : 1);
        expect(await h.cache.read(), isEmpty);
        expect(
          await h.messages.readPendingChatDeletions(ownerUserId: 'owner'),
          isEmpty,
        );
        expect(h.remote.fetchCalls, 0);
      },
    );
  }

  test(
    'concurrent identical reads share one RPC regardless of ID order',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false), _chat('b', false)]);
      h.remote.writeGate = Completer<void>();
      final first = h.repository.markAsRead({'a', 'b'});
      final second = h.repository.markAsRead({'b', 'a'});
      await h.remote.writeStarted.future;
      h.remote.writeGate!.complete();
      await Future.wait([first, second]);
      expect(h.remote.readCalls, 1);
      expect(
        (await h.cache.read()).map((chat) => chat.unreadCount),
        everyElement(0),
      );
    },
  );

  test('failed read retains cache and can be retried', () async {
    final h = await _Harness.create();
    await h.cache.replaceAll([_chat('a', false)]);
    h.remote.fail = true;
    await expectLater(h.repository.markAsRead({'a'}), throwsStateError);
    expect((await h.cache.read()).single.unreadCount, 3);
    h.remote.fail = false;
    await h.repository.markAsRead({'a'});
    expect((await h.cache.read()).single.unreadCount, 0);
    expect(h.remote.readCalls, 2);
  });

  test('an in-flight stale summary cannot undo read completion', () async {
    final h = await _Harness.create();
    await h.cache.replaceAll([_chat('a', false)]);
    h.remote.fetchGate = Completer<List<Chat>>();
    final subscription = h.repository.watchChats().listen((_) {});
    addTearDown(subscription.cancel);
    await h.remote.fetchStarted.future;
    final read = h.repository.markAsRead({'a'});
    await h.remote.writeStarted.future;
    h.remote.fetchGate!.complete([_chat('a', false)]);
    await read;
    expect((await h.cache.read()).single.unreadCount, 0);
    expect(h.remote.fetchCalls, 1);
    await subscription.cancel();
  });

  test(
    'account switch rejects late read completion without touching either cache',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false)]);
      await h.cache.replaceAll([_chat('a', false)], ownerUserId: 'other');
      h.remote.writeGate = Completer<void>();
      final read = expectLater(
        h.repository.markAsRead({'a'}),
        throwsA(isA<StaleAccountSessionException>()),
      );
      await h.remote.writeStarted.future;
      h.account.setAuthenticatedUser('other');
      h.remote.writeGate!.complete();
      await read;
      expect((await h.cache.read(ownerUserId: 'owner')).single.unreadCount, 3);
      expect((await h.cache.read(ownerUserId: 'other')).single.unreadCount, 3);
    },
  );

  test(
    'all bulk actions reject 51 IDs before writes or pending deletions',
    () async {
      final h = await _Harness.create();
      final ids = {for (var i = 0; i < 51; i++) '$i'};
      // Matching mute rows must not bypass the limit on the original selection.
      await h.cache.replaceAll([for (final id in ids) _chat(id, true)]);
      await expectLater(h.repository.markAsRead(ids), throwsArgumentError);
      await expectLater(h.repository.deleteChats(ids), throwsArgumentError);
      await expectLater(
        h.repository.setMuted(ids, isMuted: true),
        throwsArgumentError,
      );
      expect(h.remote.readCalls, 0);
      expect(h.remote.hideCalls, 0);
      expect(h.remote.calls, isEmpty);
      expect(
        await h.messages.readPendingChatDeletions(ownerUserId: 'owner'),
        isEmpty,
      );
      expect(await h.cache.read(), hasLength(51));
    },
  );

  test(
    'read completion keeps messages received during the RPC unread',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([
        _chat('a', false).copyWith(lastMessageId: 'old'),
      ]);
      h.remote.writeGate = Completer<void>();
      final read = h.repository.markAsRead({'a'});
      await h.remote.writeStarted.future;
      await h.cache.replaceAll([
        _chat('a', false).copyWith(lastMessageId: 'new', unreadCount: 4),
      ]);
      h.remote.writeGate!.complete();
      await read;
      expect((await h.cache.read()).single.unreadCount, 4);
    },
  );

  test(
    'read accepts a stale zero cache and uses only one remote write',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false).copyWith(unreadCount: 0)]);
      await h.repository.markAsRead({'a'});
      expect(h.remote.readCalls, 1);
      expect(h.remote.fetchCalls, 0);
    },
  );

  test(
    'filters matching rows and writes one explicit batch without reading messages',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([
        _chat('a', false),
        _chat('b', true),
        _chat('c', true),
      ]);
      await h.repository.setMuted({'a', 'b'}, isMuted: false);
      expect(h.remote.calls, hasLength(1));
      expect(h.remote.calls.single.ids, {'b'});
      expect(h.remote.calls.single.isMuted, false);
      final rows = {for (final chat in await h.cache.read()) chat.id: chat};
      expect(rows['a']!.isMuted, false);
      expect(rows['b']!.isMuted, false);
      expect(rows['c']!.isMuted, true);
      expect(rows['b']!.lastMessage, 'unchanged');
      expect(rows['b']!.unreadCount, 3);
      await h.repository.setMuted({'a', 'b'}, isMuted: false);
      expect(h.remote.calls, hasLength(1));
      expect(h.remote.fetchCalls, 0);
    },
  );

  test(
    'serializes identical writes and never re-inverts a realtime-updated cache',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false)]);
      h.remote.writeGate = Completer<void>();
      final first = h.repository.setMuted({'a'}, isMuted: true);
      final second = h.repository.setMuted({'a'}, isMuted: true);
      await h.remote.writeStarted.future;
      await h.cache.setMuted({'a'}, isMuted: true);
      h.remote.writeGate!.complete();
      await Future.wait([first, second]);
      expect(h.remote.calls, hasLength(1));
      expect((await h.cache.read()).single.isMuted, true);
    },
  );

  test(
    'a failed write preserves cache and does not poison the next request',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false)]);
      h.remote.fail = true;
      await expectLater(
        h.repository.setMuted({'a'}, isMuted: true),
        throwsStateError,
      );
      expect((await h.cache.read()).single.isMuted, false);
      h.remote.fail = false;
      await h.repository.setMuted({'a'}, isMuted: true);
      expect((await h.cache.read()).single.isMuted, true);
      expect(h.remote.calls, hasLength(2));
    },
  );

  test(
    'account switch rejects both completion and queued writes from the old account',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false)]);
      await h.cache.replaceAll([_chat('a', false)], ownerUserId: 'other');
      h.remote.writeGate = Completer<void>();
      final first = expectLater(
        h.repository.setMuted({'a'}, isMuted: true),
        throwsA(isA<StaleAccountSessionException>()),
      );
      final queued = expectLater(
        h.repository.setMuted({'a'}, isMuted: true),
        throwsA(isA<StaleAccountSessionException>()),
      );
      await h.remote.writeStarted.future;
      h.account.setAuthenticatedUser('other');
      h.remote.writeGate!.complete();
      await Future.wait([first, queued]);
      expect(h.remote.calls, hasLength(1));
      expect((await h.cache.read(ownerUserId: 'owner')).single.isMuted, false);
      expect((await h.cache.read(ownerUserId: 'other')).single.isMuted, false);
    },
  );

  test(
    'an in-flight stale summary cannot overwrite an accepted mute; no extra fetch',
    () async {
      final h = await _Harness.create();
      await h.cache.replaceAll([_chat('a', false)]);
      h.remote.fetchGate = Completer<List<Chat>>();
      final subscription = h.repository.watchChats().listen((_) {});
      addTearDown(subscription.cancel);
      await h.remote.fetchStarted.future;
      final operation = h.repository.setMuted({'a'}, isMuted: true);
      await h.remote.writeStarted.future;
      h.remote.fetchGate!.complete([_chat('a', false)]);
      await operation;
      expect((await h.cache.read()).single.isMuted, true);
      expect(h.remote.fetchCalls, 1);
      expect(h.remote.calls, hasLength(1));
      await subscription.cancel();
    },
  );

  test(
    'unknown locally created chat is sent, while empty and oversized batches are not',
    () async {
      final h = await _Harness.create();
      await h.repository.setMuted({}, isMuted: true);
      await expectLater(
        h.repository.setMuted({
          for (var i = 0; i < 51; i++) '$i',
        }, isMuted: true),
        throwsArgumentError,
      );
      expect(h.remote.calls, isEmpty);
      await h.repository.setMuted({'new-direct'}, isMuted: true);
      expect(h.remote.calls.single.ids, {'new-direct'});
      expect(await h.cache.read(), isEmpty);
    },
  );

  test(
    'remote uses exactly one POST with explicit boolean and selected IDs',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://localhost',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204, request: request);
        }),
      );
      addTearDown(client.dispose);
      final remote = ChatsRemoteDataSource(client: client, talker: Talker());
      await remote.setMuted({'a', 'b'}, isMuted: false);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/rpc/set_conversations_muted');
      expect(jsonDecode(requests.single.body), {
        'conversation_ids': ['a', 'b'],
        'muted': false,
      });
    },
  );
}

class _Harness {
  _Harness(
    this.repository,
    this.cache,
    this.remote,
    this.account,
    this.messages,
  );
  final ChatsRepository repository;
  final ChatsCacheDataSource cache;
  final _Remote remote;
  final AccountSessionController account;
  final ChatCacheDataSource messages;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final account = AccountSessionController(initialUserId: 'owner');
    final media = MediaCacheService(database: database);
    addTearDown(media.dispose);
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: preferences,
      talker: Talker(),
      env: const {},
      database: database,
      accountSessionController: account,
    );
    final cache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final messages = ChatCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final remote = _Remote();
    final chatRemote = ChatRemoteDataSource(
      client: SupabaseClient('http://localhost', 'test-key'),
    );
    return _Harness(
      ChatsRepository(
        config: config,
        cache: cache,
        remote: remote,
        mediaCache: media,
        chatCache: messages,
        accountSessionController: account,
        conversationSync: ConversationSyncService(
          cache: messages,
          remote: chatRemote,
          hydrator: ChatMessageHydrator(
            config: config,
            remote: chatRemote,
            mediaCache: media,
          ),
          chatsCache: cache,
          accountSessionController: account,
        ),
      ),
      cache,
      remote,
      account,
      messages,
    );
  }
}

class _Remote extends ChatsRemoteDataSource {
  _Remote()
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );
  final calls = <({Set<String> ids, bool isMuted})>[];
  final writeStarted = Completer<void>();
  final fetchStarted = Completer<void>();
  Completer<void>? writeGate;
  Completer<List<Chat>>? fetchGate;
  bool fail = false;
  int fetchCalls = 0;
  int readCalls = 0;
  int hideCalls = 0;
  @override
  Future<void> markAsRead(Set<String> ids) async {
    readCalls++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (fail) throw StateError('offline');
    await writeGate?.future;
  }

  @override
  Future<void> hideChats(Set<String> ids, {required DateTime clearedAt}) async {
    hideCalls++;
    if (fail) throw StateError('offline');
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    calls.add((ids: Set.of(ids), isMuted: isMuted));
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (fail) throw StateError('offline');
    await writeGate?.future;
  }

  @override
  Future<List<Chat>> fetchChats() async {
    fetchCalls++;
    if (!fetchStarted.isCompleted) fetchStarted.complete();
    return await fetchGate?.future ?? [];
  }

  @override
  Stream<ConversationChange> watchChanges() => const Stream.empty();
}

Chat _chat(String id, bool muted) => Chat(
  id: id,
  userName: id,
  lastMessage: 'unchanged',
  lastMessageTime: DateTime(2026),
  unreadCount: 3,
  isOnline: false,
  isLastMessageFromMe: false,
  isMuted: muted,
);
