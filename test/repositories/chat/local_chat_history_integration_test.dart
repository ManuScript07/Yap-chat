// Opt-in real HTTP/SQLite integration. Provisioned and cleaned up by
// supabase/benchmarks/chat_history_local.mjs --flutter. No production config.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:uuid/uuid.dart';

void main() {
  final env = Platform.environment;
  final enabled = env['CHAT_TEST_TOKEN'] != null;
  test(
    'real local RPC + Drift: bounded head, gaps, revisits, deletion, offline',
    () async {
      final owner = env['CHAT_TEST_USER']!;
      final chat = env['CHAT_TEST_CHAT']!;
      final target = env['CHAT_TEST_TARGET']!;
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final transport = _Transport();
      final client = SupabaseClient(
        'http://127.0.0.1:54321',
        env['CHAT_TEST_ANON']!,
        httpClient: transport,
        accessToken: () async => env['CHAT_TEST_TOKEN']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final account = AccountSessionController(initialUserId: owner);
      final cache = ChatCacheDataSource(
        database: db,
        userIdProvider: () => owner,
      );
      final chats = ChatsCacheDataSource(
        database: db,
        userIdProvider: () => owner,
      );
      final media = MediaCacheService(database: db);
      final config = AppConfig(
        environment: AppEnvironment.local,
        preferences: await SharedPreferences.getInstance(),
        talker: Talker(settings: TalkerSettings(enabled: false)),
        env: const {},
        database: db,
        accountSessionController: account,
      );
      final remote = _LocalRemote(client, owner);
      final sync = ConversationSyncService(
        cache: cache,
        remote: remote,
        hydrator: ChatMessageHydrator(
          config: config,
          remote: remote,
          mediaCache: media,
        ),
        chatsCache: chats,
        accountSessionController: account,
      );
      final repo = ChatRepository(
        config: config,
        cache: cache,
        remote: remote,
        mediaProcessor: const ChatMediaProcessor(),
        mediaCache: media,
        syncService: sync,
        chatsCache: chats,
        localMediaRepository: _LocalMedia(),
        accountSessionController: account,
      );
      try {
        final head = await repo
            .getMessagesStream(chat)
            .firstWhere((m) => m.length == 60);
        expect(transport.count('get_conversation_messages'), 1);
        final pages = await Future.wait([
          repo.loadHistoryOlder(chat, head.last),
          repo.loadHistoryOlder(chat, head.last),
        ]);
        expect(pages.first, hasLength(60));
        expect(pages.first, pages.last);
        expect(transport.count('get_conversation_messages'), 2);
        expect({
          ...head.map((m) => m.id),
          ...pages.first.map((m) => m.id),
        }, hasLength(120));
        expect(await repo.loadHistoryOlder(chat, head.last), pages.first);
        expect(transport.count('get_conversation_messages'), 2);

        // Window remains remote-only, including pagination on either side.
        final cachedCount = (await db.select(db.cachedMessages).get()).length;
        final window = await repo.loadMessageWindow(chat, target);
        expect(window, hasLength(60));
        expect(window.any((m) => m.id == target), isTrue);
        expect(await repo.loadWindowOlder(chat, window.last), hasLength(60));
        expect(await repo.loadWindowNewer(chat, window.first), hasLength(60));
        expect((await db.select(db.cachedMessages).get()).length, cachedCount);

        // Read only one incoming visible message, not the rest of the page.
        final incoming = pages.first.where((m) => !m.isMine).take(2).toList();
        await remote.markVisibleMessagesRead(chat, {incoming.first.id});
        final refreshed = await remote.fetchMessages(
          chat,
          beforeTimestamp: head.last.timestamp,
          beforeMessageId: head.last.id,
        );
        expect(
          refreshed.firstWhere((m) => m.id == incoming.first.id).readAt,
          isNotNull,
        );
        expect(
          refreshed.firstWhere((m) => m.id == incoming.last.id).readAt,
          isNull,
        );
        final reaction = await remote.setReaction(
          chatId: chat,
          messageId: incoming.first.id,
          operationId: const Uuid().v4(),
          code: ReactionCode.heart,
          expectedRevision: 0,
        );
        expect(reaction.applied, isTrue);
        final states = await remote.fetchVisibleMessageStates(chat, [
          incoming.first.id,
        ]);
        expect(states[incoming.first.id], reaction.state);

        // A remote deletion in history must be removed from an old local page.
        await remote.deleteMessage(incoming.last.id, deleteForEveryone: false);
        final authoritative = await remote.fetchMessages(
          chat,
          beforeTimestamp: head.last.timestamp,
          beforeMessageId: head.last.id,
        );
        await cache.storeHistoryPage(
          chat,
          authoritative,
          ownerUserId: owner,
          boundary: head.last,
          older: true,
        );
        expect(
          await cache.readMessage(incoming.last.id, currentUserId: owner),
          isNull,
        );
        expect(
          (await repo.loadHistoryOlder(chat, head.last)).map((m) => m.id),
          isNot(contains(incoming.last.id)),
        );

        // Disconnected intervals are not silently combined after an offline gap.
        await cache.clearConversations({chat});
        await cache.replaceRecentMessages(chat, window);
        await sync.synchronizeRecent(chat);
        final before = transport.count('get_conversation_messages');
        final missingMiddle = await repo.loadHistoryOlder(chat, head.last);
        expect(transport.count('get_conversation_messages'), before + 1);
        expect(missingMiddle.map((m) => m.id), authoritative.map((m) => m.id));

        transport.offline = true;
        final calls = transport.calls.length;
        expect(await repo.loadHistoryOlder(chat, head.last), missingMiddle);
        expect(
          transport.calls.length,
          calls,
        ); // Proven cache revisit is HTTP-free.
        expect(
          await cache
              .watchMessages(chat, currentUserId: owner, limit: 60)
              .first,
          hasLength(60),
        );
        // ignore: avoid_print
        print('LOCAL_REPOSITORY_OK ${transport.counts}');
      } finally {
        await repo.pauseNetwork();
        media.dispose();
        await client.dispose();
        transport.close();
        await db.close();
      }
    },
    skip: enabled ? false : 'Run with the local Docker fixture runner',
  );
}

class _LocalRemote extends ChatRemoteDataSource {
  _LocalRemote(SupabaseClient client, this.owner) : super(client: client);
  final String owner;
  @override
  String get currentUserId => owner;
}

class _Transport extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<String> calls = [];
  bool offline = false;
  int count(String name) => calls.where((p) => p.endsWith('/$name')).length;
  Map<String, int> get counts => {
    for (final p in calls) p: calls.where((v) => v == p).length,
  };
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host != '127.0.0.1' || request.url.port != 54321) {
      throw StateError('This test permits local Supabase only');
    }
    if (offline) throw const SocketException('Deliberate local test offline');
    calls.add(request.url.path);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class _LocalMedia implements ILocalMediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
