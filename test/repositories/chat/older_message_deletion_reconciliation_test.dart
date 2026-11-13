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
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_repository.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

void main() {
  test(
    'a chat with only its newest page makes no visibility request',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final recent = List.generate(
        60,
        (index) => _message('recent-$index', index),
      );
      harness.remote.recent = recent;

      final fetched = await harness.sync.synchronizeRecent('chat');
      await Future.wait([
        harness.sync.reconcileVisibleMessages(
          'chat',
          fetched.map((m) => m.id).toSet(),
        ),
        harness.sync.reconcileVisibleMessages(
          'chat',
          fetched.map((m) => m.id).toSet(),
        ),
      ]);

      expect(harness.remote.visibilityRequests, isEmpty);
    },
  );

  test(
    'viewing an older cached page repairs a deletion missed offline',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final recent = List.generate(
        60,
        (index) => _message('recent-$index', index),
      );
      final deleted = _message('deleted-older', 60);
      final retained = _message('retained-older', 61);
      final localOnly = _message('local-only', 62).copyWith(isLocalOnly: true);
      harness.remote.recent = recent;
      harness.remote.visibleIds = {retained.id};
      await harness.cache.upsertMessages([
        ...recent,
        deleted,
        retained,
        localOnly,
      ]);

      await harness.sync.synchronizeRecent('chat');
      await Future.wait([
        harness.sync.reconcileVisibleMessages('chat', {
          deleted.id,
          retained.id,
        }),
        harness.sync.reconcileVisibleMessages('chat', {
          deleted.id,
          retained.id,
        }),
      ]);

      final ids = (await harness.cache.readMessages(
        'chat',
        currentUserId: 'owner',
      )).map((message) => message.id).toSet();
      expect(ids, isNot(contains(deleted.id)));
      expect(ids, contains(retained.id));
      expect(ids, contains(localOnly.id));
      expect(harness.remote.visibilityRequests, [
        {deleted.id, retained.id},
      ]);
      expect(harness.remote.recentRequests, 1);

      // Repeated viewport checks do not re-query validated messages.
      await harness.sync.reconcileVisibleMessages('chat', {
        retained.id,
        localOnly.id,
      });
      expect(harness.remote.visibilityRequests.length, 1);
    },
  );

  test(
    'a deleted realtime ID removes cached old history and reply previews',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final deleted = _message('deleted-older', 80);
      final reply = _message('reply', 0).copyWith(
        replyTo: MessageReply(
          messageId: deleted.id,
          senderId: 'peer',
          isMine: false,
          type: MessageType.text,
          text: deleted.text,
        ),
      );
      await harness.cache.upsertMessages([deleted, reply]);
      final repository = harness.createRepository();
      final deletion = repository
          .watchHistoryChanges('chat')
          .firstWhere((change) => change.deletedMessageId == deleted.id);
      final removedFromCache = harness.cache
          .watchMessages('chat', currentUserId: 'owner')
          .firstWhere((messages) => messages.every((m) => m.id != deleted.id));

      harness.realtime.emit(
        UserConversationRealtimeEvent(
          conversationId: 'chat',
          reason: 'deleted',
          messageId: deleted.id,
        ),
      );
      await deletion.timeout(const Duration(seconds: 2));
      await removedFromCache.timeout(const Duration(seconds: 2));
      expect(
        (await harness.cache.readMessage(
          reply.id,
          currentUserId: 'owner',
        ))?.replyTo,
        isNull,
      );

      // An older in-flight page must not reinsert the deleted message.
      await harness.cache.upsertMessages([deleted]);
      expect(
        await harness.cache.readMessage(deleted.id, currentUserId: 'owner'),
        isNull,
      );
    },
  );

  test('opening checks the recent page but not unseen old history', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final recent = List.generate(
      60,
      (index) => _message('recent-$index', index),
    );
    final deleted = _message('deleted-older', 60);
    harness.remote.recent = recent;
    await harness.cache.upsertMessages([...recent, deleted]);
    final repository = harness.createRepository();

    final subscription = repository.getMessagesStream('chat').listen((_) {});
    addTearDown(subscription.cancel);
    await harness.cache
        .watchMessages('chat', currentUserId: 'owner')
        .firstWhere((messages) => messages.length == 61)
        .timeout(const Duration(seconds: 2));
    expect(harness.remote.visibilityRequests, isEmpty);
    expect(
      await harness.cache.readMessage(deleted.id, currentUserId: 'owner'),
      isNotNull,
    );

    await repository.reconcileVisibleMessages('chat', {deleted.id});
    expect(
      await harness.cache.readMessage(deleted.id, currentUserId: 'owner'),
      isNull,
    );
    expect(harness.remote.visibilityRequests, [
      {deleted.id},
    ]);
  });

  test('only viewed older pages are checked in bounded batches', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final recent = List.generate(
      60,
      (index) => _message('recent-$index', index),
    );
    final older = List.generate(
      205,
      (index) => _message('older-$index', 60 + index),
    );
    harness.remote.recent = recent;
    harness.remote.visibleIds = older.map((message) => message.id).toSet();
    await harness.cache.upsertMessages([...recent, ...older]);

    await harness.sync.synchronizeRecent('chat');
    expect(harness.remote.visibilityRequests, isEmpty);
    await harness.sync.reconcileVisibleMessages(
      'chat',
      older.take(60).map((message) => message.id).toSet(),
    );
    expect(harness.remote.visibilityRequests.map((batch) => batch.length), [
      60,
    ]);
    expect(
      (await harness.cache.readMessages('chat', currentUserId: 'owner')).length,
      265,
    );
  });

  test('resuming rechecks a viewed old page once', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final recent = List.generate(
      60,
      (index) => _message('recent-$index', index),
    );
    final older = _message('older', 60);
    harness.remote.recent = recent;
    harness.remote.visibleIds = {older.id};
    await harness.cache.upsertMessages([...recent, older]);

    await harness.sync.synchronizeRecent('chat');
    await harness.sync.reconcileVisibleMessages('chat', {older.id});
    await harness.sync.reconcileVisibleMessages('chat', {older.id});
    expect(harness.remote.visibilityRequests.length, 1);

    harness.sync.resetVisibleValidation('chat');
    await harness.sync.synchronizeRecent('chat');
    await harness.sync.reconcileVisibleMessages('chat', {older.id});
    expect(harness.remote.visibilityRequests.length, 2);
  });

  test('Realtime resubscription invalidates prior viewport checks', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final older = _message('older', 60);
    harness.remote.visibleIds = {older.id};
    await harness.cache.upsertMessages([older]);
    await harness.sync.reconcileVisibleMessages('chat', {older.id});
    final repository = harness.createRepository();
    final reconnected = repository
        .watchHistoryChanges('chat')
        .firstWhere((change) => change.reconnected);
    harness.realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: 'chat',
        reason: 'subscribed',
      ),
    );
    await reconnected.timeout(const Duration(seconds: 2));
    await repository.reconcileVisibleMessages('chat', {older.id});
    expect(harness.remote.visibilityRequests.length, 2);
  });

  test(
    'a failed visibility request preserves offline cached history',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final recent = List.generate(
        60,
        (index) => _message('recent-$index', index),
      );
      final older = _message('older', 60);
      harness.remote.recent = recent;
      harness.remote.failVisibility = true;
      await harness.cache.upsertMessages([...recent, older]);

      await harness.sync.synchronizeRecent('chat');
      await expectLater(
        harness.sync.reconcileVisibleMessages('chat', {older.id}),
        throwsStateError,
      );

      expect(
        await harness.cache.readMessage(older.id, currentUserId: 'owner'),
        isNotNull,
      );
    },
  );
}

ChatMessage _message(String id, int secondsAgo) => ChatMessage(
  id: id,
  chatId: 'chat',
  senderId: 'peer',
  text: id,
  timestamp: DateTime.utc(
    2026,
    9,
    26,
    12,
  ).subtract(Duration(seconds: secondsAgo)),
  isMine: false,
);

class _Harness {
  _Harness({
    required this.database,
    required this.account,
    required this.cache,
    required this.chatsCache,
    required this.mediaCache,
    required this.config,
    required this.remote,
    required this.realtime,
    required this.sync,
  });

  final AppDatabase database;
  final AccountSessionController account;
  final ChatCacheDataSource cache;
  final ChatsCacheDataSource chatsCache;
  final MediaCacheService mediaCache;
  final AppConfig config;
  final _FakeRemote remote;
  final _FakeRealtime realtime;
  final ConversationSyncService sync;

  ChatRepository createRepository() => ChatRepository(
    config: config,
    cache: cache,
    remote: remote,
    mediaProcessor: const ChatMediaProcessor(),
    mediaCache: mediaCache,
    syncService: sync,
    chatsCache: chatsCache,
    localMediaRepository: const _NoopLocalMediaRepository(),
    accountSessionController: account,
    userRealtime: realtime,
  );

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final account = AccountSessionController(initialUserId: 'owner');
    final cache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final chatsCache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final mediaCache = MediaCacheService(database: database);
    final config = AppConfig(
      environment: AppEnvironment.local,
      preferences: preferences,
      talker: Talker(),
      env: const {},
      database: database,
      accountSessionController: account,
    );
    final remote = _FakeRemote();
    final realtime = _FakeRealtime();
    final sync = ConversationSyncService(
      cache: cache,
      remote: remote,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: remote,
        mediaCache: mediaCache,
      ),
      chatsCache: chatsCache,
      accountSessionController: account,
    );
    return _Harness(
      database: database,
      account: account,
      cache: cache,
      chatsCache: chatsCache,
      mediaCache: mediaCache,
      config: config,
      remote: remote,
      realtime: realtime,
      sync: sync,
    );
  }

  Future<void> dispose() async {
    await realtime.dispose();
    mediaCache.dispose();
    await database.close();
  }
}

class _FakeRemote extends ChatRemoteDataSource {
  _FakeRemote() : super(client: SupabaseClient('http://localhost', 'test-key'));

  List<ChatMessage> recent = const [];
  Set<String> visibleIds = const {};
  bool failVisibility = false;
  int recentRequests = 0;
  final List<Set<String>> visibilityRequests = [];

  @override
  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    recentRequests++;
    return recent;
  }

  @override
  Future<Map<String, MessageReactionState>> fetchVisibleMessageStates(
    String chatId,
    List<String> messageIds,
  ) async {
    visibilityRequests.add(messageIds.toSet());
    if (failVisibility) throw StateError('offline');
    return {
      for (final id in messageIds.toSet().intersection(visibleIds))
        id: const MessageReactionState(),
    };
  }
}

class _FakeRealtime extends UserRealtimeDataSource {
  _FakeRealtime()
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );

  final _events = StreamController<UserConversationRealtimeEvent>.broadcast();

  @override
  Stream<UserConversationRealtimeEvent> watchConversationEvents() =>
      _events.stream;

  void emit(UserConversationRealtimeEvent event) => _events.add(event);

  @override
  Future<void> dispose() async {
    await _events.close();
    await super.dispose();
  }
}

class _NoopLocalMediaRepository implements ILocalMediaRepository {
  const _NoopLocalMediaRepository();

  @override
  RecordedAudio? getVoiceDraft(String chatId) => null;
  @override
  Future<RecordedAudio?> saveVoiceDraft(
    String chatId,
    RecordedAudio audio,
  ) async => audio;
  @override
  Future<void> removeVoiceDraft(
    String chatId, {
    bool deleteFile = true,
  }) async {}

  @override
  Future<void> removeVoiceDraftByPath(String audioPath) async {}

  @override
  Future<void> clearPendingChatId() async {}
  @override
  Future<void> clearUser(String ownerUserId) async {}
  @override
  Future<void> collectGarbage() async {}
  @override
  Future<String?> consumePendingChatId() async => null;
  @override
  Future<String?> consumePendingMedia() async => null;
  @override
  Future<void> deleteMedia(String path) async {}
  @override
  List<String> getRecentMediaPaths() => const [];
  @override
  Future<String?> persistMedia(String sourcePath) async => null;
  @override
  Future<void> savePendingChatId(String chatId) async {}
  @override
  Future<void> savePendingMedia(String path) async {}
}
