import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  late _Harness h;
  setUp(() async => h = await _Harness.create());
  tearDown(() => h.dispose());

  test(
    'fresh history page removes an already cached server deletion',
    () async {
      h.remote.messages[0] = h.remote.messages[0].copyWith(
        replyTo: const MessageReply(
          messageId: 'm65',
          senderId: 'peer',
          isMine: false,
          type: MessageType.text,
          text: 'removed',
        ),
      );
      await h.cache.upsertMessages(h.remote.messages);
      final head = await h.sync.synchronizeRecent('chat');
      await h.cache.enqueueReaction(
        ownerUserId: 'owner',
        chatId: 'chat',
        messageId: 'm65',
        operationId: 'reaction-op',
        code: ReactionCode.heart,
        expectedRevision: 0,
        dueAt: DateTime(2030),
      );
      h.remote.messages.removeWhere((m) => m.id == 'm65');
      final page = await h.repository.loadHistoryOlder('chat', head.last);
      expect(page, hasLength(60));
      expect(page.map((m) => m.id), isNot(contains('m65')));
      expect(page.last.id, 'm120');
      expect(await h.cache.readMessage('m65', currentUserId: 'owner'), isNull);
      expect(
        (await h.cache.readMessage('m0', currentUserId: 'owner'))?.replyTo,
        isNull,
      );
      expect(
        await h.cache.readPendingReaction('m65', ownerUserId: 'owner'),
        isNull,
      );
    },
  );

  test(
    'history metadata refresh preserves matching cached image paths',
    () async {
      h.remote.messages[70] = h.remote.messages[70].copyWith(
        type: MessageType.image,
        mediaStoragePaths: ['chat/image-70'],
      );
      await h.cache.upsertMessage(
        h.remote.messages[70].copyWith(mediaUrls: ['cached/image-70']),
      );
      final head = await h.sync.synchronizeRecent('chat');
      final page = await h.repository.loadHistoryOlder('chat', head.last);
      expect(page.firstWhere((m) => m.id == 'm70').mediaUrls, [
        'cached/image-70',
      ]);
      expect(h.hydrator.calls, 1);
    },
  );

  test(
    'an in-flight stale page cannot resurrect a tombstoned history row',
    () async {
      final head = await h.sync.synchronizeRecent('chat');
      h.remote.gate = Completer<void>();
      final request = h.repository.loadHistoryOlder('chat', head.last);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await h.cache.removeMessages('chat', {'m65'}, ownerUserId: 'owner');
      h.remote.gate!.complete();
      final page = await request;
      expect(page, hasLength(59));
      expect(page.map((m) => m.id), isNot(contains('m65')));
      expect(await h.cache.readMessage('m65', currentUserId: 'owner'), isNull);
    },
  );

  test(
    'opening a large cached chat emits 60 rows and one recent RPC',
    () async {
      await h.cache.upsertMessages(h.remote.messages);
      final emissions = <List<ChatMessage>>[];
      final stream = h.repository
          .getMessagesStream('chat')
          .listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await stream.cancel();
      expect(emissions, isNotEmpty);
      expect(emissions.every((rows) => rows.length == 60), isTrue);
      expect(h.remote.pages, 1);
      expect(h.remote.windows, 0);
    },
  );

  test(
    'coalesces frontier requests; cached revisit has no RPC or media hydration',
    () async {
      final head = await h.sync.synchronizeRecent('chat');
      final pages = await Future.wait([
        h.repository.loadHistoryOlder('chat', head.last),
        h.repository.loadHistoryOlder('chat', head.last),
      ]);
      expect(pages.first, h.remote.messages.skip(60).take(60).toList());
      expect(pages.last, pages.first);
      expect(h.remote.pages, 2);
      expect(h.hydrator.calls, 1); // Only the original recent-page sync.
      expect(
        await h.repository.loadHistoryOlder('chat', head.last),
        pages.first,
      );
      expect(h.remote.pages, 2);
      expect(h.hydrator.calls, 1);
      await h.repository.refreshHistoryMessages(
        'chat',
        pages.first.map((m) => m.id).toSet(),
      );
      expect(
        h.remote.visibilityChecks,
        0,
      ); // Fresh RPC page is already validated.
    },
  );

  test(
    'long offline gap loads missing middle rather than jumping to old cache',
    () async {
      await h.cache.replaceRecentMessages(
        'chat',
        h.remote.messages.skip(180).take(60).toList(),
      );
      final head = await h.sync.synchronizeRecent('chat');
      final page = await h.repository.loadHistoryOlder('chat', head.last);
      expect(page.first.id, 'm60');
      expect(page.last.id, 'm119');
      expect(h.remote.pages, 2);
    },
  );

  test(
    'offline unknown cache remains scrollable without claiming coverage',
    () async {
      await h.cache.upsertMessages(h.remote.messages);
      h.remote.offline = true;
      final boundary = h.remote.messages[59];
      expect(
        await h.repository.loadHistoryOlder('chat', boundary),
        h.remote.messages.skip(60).take(60).toList(),
      );
      expect(
        await h.repository.loadHistoryOlder('chat', boundary),
        hasLength(60),
      );
      expect(h.remote.pages, 1); // Failure backoff, no polling or retry storm.
      expect(await h.db.select(h.db.cachedChatHistoryRanges).get(), isEmpty);
    },
  );

  test('stale session cannot return or commit an old account page', () async {
    final head = await h.sync.synchronizeRecent('chat');
    h.remote.gate = Completer<void>();
    final request = h.repository.loadHistoryOlder('chat', head.last);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    h.account.setAuthenticatedUser('other');
    final rejected = expectLater(
      request,
      throwsA(isA<StaleAccountSessionException>()),
    );
    h.remote.gate!.complete();
    await rejected;
    expect(await h.cache.readMessage('m60', currentUserId: 'owner'), isNull);
    expect(await h.cache.readMessage('m60', currentUserId: 'other'), isNull);
  });

  test(
    'cached history viewport reconciliation removes missed deletes',
    () async {
      final head = await h.sync.synchronizeRecent('chat');
      final older = await h.repository.loadHistoryOlder('chat', head.last);
      h.remote.messages.removeWhere((m) => m.id == older[5].id);
      h.sync.resetVisibleValidation('chat'); // A deletion missed while offline.
      final ids = older.map((m) => m.id).toSet();
      final refreshed = await h.repository.refreshHistoryMessages('chat', ids);
      expect(refreshed, hasLength(59));
      expect(refreshed.map((m) => m.id), isNot(contains(older[5].id)));
      expect(h.remote.visibilityChecks, 1);
      expect(h.remote.windows, 0);
    },
  );

  test(
    'distant reply windows never populate ordinary-history rows or coverage',
    () async {
      final target = h.remote.messages[300];
      final window = await h.repository.loadMessageWindow('chat', target.id);
      expect(window, contains(target));
      await h.repository.loadWindowOlder('chat', window.last);
      expect(
        await h.cache.readMessage(target.id, currentUserId: 'owner'),
        isNull,
      );
      expect(await h.db.select(h.db.cachedChatHistoryRanges).get(), isEmpty);
      expect(h.hydrator.calls, 0);
    },
  );

  test(
    'cached replies read a bounded local window without a remote request',
    () async {
      final head = await h.sync.synchronizeRecent('chat');
      await h.repository.loadHistoryOlder('chat', head.last);
      final requests = h.remote.pages;
      final window = await h.repository.readCachedHistoryWindow('chat', 'm80');
      expect(window, hasLength(60));
      expect(window!.any((m) => m.id == 'm80'), isTrue);
      expect(h.remote.pages, requests);
      expect(h.remote.windows, 0);
      expect(
        await h.repository.readCachedHistoryWindow('chat', 'm500'),
        isNull,
      );
    },
  );

  test(
    'legacy cached reply is available offline but not declared verified',
    () async {
      await h.cache.upsertMessages(h.remote.messages);
      expect(
        await h.repository.readCachedHistoryWindow('chat', 'm300'),
        isNull,
      );
      final window = await h.repository.readCachedHistoryWindow(
        'chat',
        'm300',
        allowUnverified: true,
      );
      expect(window, hasLength(60));
      expect(h.remote.pages, 0);
      expect(h.remote.windows, 0);
      expect(await h.db.select(h.db.cachedChatHistoryRanges).get(), isEmpty);
    },
  );

  test(
    'account cleanup removes history ranges without touching another owner',
    () async {
      final recent = h.remote.messages.take(60).toList();
      await h.cache.replaceRecentMessages('chat', recent);
      await h.cache.replaceRecentMessages('chat', recent, ownerUserId: 'other');
      await h.media.clearUser('owner');
      final rows = await h.db.select(h.db.cachedChatHistoryRanges).get();
      expect(rows, hasLength(1));
      expect(rows.single.ownerUserId, 'other');
    },
  );
}

class _Harness {
  _Harness(
    this.db,
    this.account,
    this.cache,
    this.remote,
    this.media,
    this.sync,
    this.hydrator,
    this.repository,
  );
  final AppDatabase db;
  final AccountSessionController account;
  final ChatCacheDataSource cache;
  final _Remote remote;
  final MediaCacheService media;
  final ConversationSyncService sync;
  final _Hydrator hydrator;
  final ChatRepository repository;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final account = AccountSessionController(initialUserId: 'owner');
    final cache = ChatCacheDataSource(
      database: db,
      userIdProvider: () => account.userId!,
    );
    final chats = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => account.userId!,
    );
    final media = MediaCacheService(database: db);
    final config = AppConfig(
      environment: AppEnvironment.local,
      preferences: prefs,
      talker: Talker(settings: TalkerSettings(enabled: false)),
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final remote = _Remote();
    final hydrator = _Hydrator(
      config: config,
      remote: remote,
      mediaCache: media,
    );
    final sync = ConversationSyncService(
      cache: cache,
      remote: remote,
      hydrator: hydrator,
      chatsCache: chats,
      accountSessionController: account,
    );
    final repository = ChatRepository(
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
    return _Harness(
      db,
      account,
      cache,
      remote,
      media,
      sync,
      hydrator,
      repository,
    );
  }

  Future<void> dispose() async {
    await repository.pauseNetwork();
    media.dispose();
    await db.close();
  }
}

class _Remote extends ChatRemoteDataSource {
  _Remote() : super(client: SupabaseClient('http://localhost', 'test-key'));
  final messages = [
    for (var i = 0; i < 600; i++)
      ChatMessage(
        id: 'm$i',
        chatId: 'chat',
        senderId: 'peer',
        text: 'message $i',
        isMine: false,
        timestamp: DateTime.utc(
          2026,
          10,
          18,
          12,
        ).subtract(Duration(microseconds: i * 1001)).toLocal(),
      ),
  ];
  int pages = 0;
  int windows = 0;
  int visibilityChecks = 0;
  bool offline = false;
  Completer<void>? gate;
  @override
  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    pages++;
    if (offline) throw StateError('offline');
    await gate?.future;
    return messages
        .where(
          (m) =>
              beforeTimestamp == null ||
              m.timestamp.isBefore(beforeTimestamp) ||
              (m.timestamp == beforeTimestamp &&
                  m.id.compareTo(beforeMessageId!) < 0),
        )
        .take(pageSize)
        .toList();
  }

  @override
  Future<List<ChatMessage>> fetchMessageWindow(
    String chatId, {
    String? targetMessageId,
    DateTime? afterTimestamp,
    String? afterMessageId,
  }) async {
    windows++;
    if (offline) throw StateError('offline');
    if (targetMessageId != null) {
      final index = messages.indexWhere((m) => m.id == targetMessageId);
      return index < 0
          ? []
          : messages
                .skip((index - 30).clamp(0, messages.length))
                .take(60)
                .toList();
    }
    return messages
        .where(
          (m) =>
              m.timestamp.isAfter(afterTimestamp!) ||
              (m.timestamp == afterTimestamp &&
                  m.id.compareTo(afterMessageId!) > 0),
        )
        .toList()
        .reversed
        .take(60)
        .toList()
        .reversed
        .toList();
  }

  @override
  Future<Map<String, MessageReactionState>> fetchVisibleMessageStates(
    String chatId,
    List<String> ids,
  ) async {
    visibilityChecks++;
    return {
      for (final m in messages)
        if (ids.contains(m.id)) m.id: m.reactionState,
    };
  }
}

class _Hydrator extends ChatMessageHydrator {
  _Hydrator({
    required super.config,
    required super.remote,
    required super.mediaCache,
  });
  int calls = 0;
  @override
  Future<List<ChatMessage>> hydrateAll(
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) async {
    calls++;
    return messages;
  }
}

class _LocalMedia implements ILocalMediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
