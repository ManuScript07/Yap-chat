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
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_repository.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

void main() {
  test('history pages stay raw; only requested media is hydrated', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final account = AccountSessionController(initialUserId: 'owner');
    final remote = _WindowRemote();
    final chatCache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final chatsCache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final mediaCache = MediaCacheService(database: database);
    addTearDown(mediaCache.dispose);
    final config = AppConfig(
      environment: AppEnvironment.local,
      preferences: preferences,
      talker: Talker(),
      env: const {},
      database: database,
      accountSessionController: account,
    );
    final hydrator = _CountingHydrator(
      config: config,
      remote: remote,
      mediaCache: mediaCache,
    );
    final sync = ConversationSyncService(
      cache: chatCache,
      remote: remote,
      hydrator: hydrator,
      chatsCache: chatsCache,
      accountSessionController: account,
    );
    final realtime = _FakeUserRealtime();
    addTearDown(realtime.dispose);
    final repository = ChatRepository(
      config: config,
      cache: chatCache,
      remote: remote,
      mediaProcessor: const ChatMediaProcessor(),
      mediaCache: mediaCache,
      syncService: sync,
      chatsCache: chatsCache,
      localMediaRepository: const _NoopLocalMediaRepository(),
      accountSessionController: account,
      userRealtime: realtime,
    );
    addTearDown(repository.pauseNetwork);

    final window = await repository.loadMessageWindow('chat', 'image-1');
    final older = await repository.loadWindowOlder('chat', window.last);
    final newer = await repository.loadWindowNewer('chat', window.first);
    expect(window, hasLength(60));
    expect(older, hasLength(60));
    expect(newer, hasLength(60));
    expect(hydrator.hydratedIds, isEmpty);
    expect(remote.windowRequests, 2);
    expect(remote.olderRequests, 1);

    await repository.markVisibleMessagesRead('chat', {'image-1', 'image-2'});
    expect(remote.visibleReadRequests, hasLength(1));
    expect(remote.visibleReadRequests.single.$1, 'chat');
    expect(remote.visibleReadRequests.single.$2, {'image-1', 'image-2'});

    final hydrated = await repository.hydrateWindowMedia(window.first);
    expect(hydrated.mediaUrls, ['cached:image-1']);
    expect(hydrator.hydratedIds, ['image-1']);

    final changes = repository.watchHistoryChanges('chat').asBroadcastStream();
    final received = <ChatHistoryChange>[];
    final subscription = changes.listen(received.add);
    addTearDown(subscription.cancel);
    realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: 'other-chat',
        reason: 'deleted',
        messageId: 'other-message',
      ),
    );
    realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: 'chat',
        reason: 'deleted',
        messageId: 'image-1',
      ),
    );
    realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: 'chat',
        reason: 'deleted',
      ),
    );
    realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: null,
        reason: 'subscribed',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(3));
    expect(received[0].deletedMessageId, 'image-1');
    expect(received[1].reconnected, isTrue);
    expect(received[2].reconnected, isTrue);
    expect(remote.windowRequests, 2); // Listening itself never fetches.

    account.setAuthenticatedUser('another-owner');
    realtime.emit(
      const UserConversationRealtimeEvent(
        conversationId: 'chat',
        reason: 'deleted',
        messageId: 'image-2',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(3));
  });
}

class _WindowRemote extends ChatRemoteDataSource {
  _WindowRemote()
    : super(client: SupabaseClient('http://localhost', 'test-key'));

  int windowRequests = 0;
  int olderRequests = 0;
  final List<(String, Set<String>)> visibleReadRequests = [];

  @override
  Future<void> markVisibleMessagesRead(
    String chatId,
    Set<String> messageIds,
  ) async {
    visibleReadRequests.add((chatId, Set.of(messageIds)));
  }

  @override
  Future<List<ChatMessage>> fetchMessageWindow(
    String chatId, {
    String? targetMessageId,
    DateTime? afterTimestamp,
    String? afterMessageId,
  }) async {
    windowRequests++;
    return _page(chatId);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    olderRequests++;
    return _page(chatId);
  }

  List<ChatMessage> _page(String chatId) => List.generate(
    60,
    (index) => ChatMessage(
      id: 'image-${index + 1}',
      chatId: chatId,
      senderId: 'peer',
      text: '',
      timestamp: DateTime.utc(
        2026,
        9,
        24,
        12,
      ).subtract(Duration(minutes: index)),
      isMine: false,
      type: MessageType.image,
      mediaStoragePaths: ['image-${index + 1}.jpg'],
    ),
  );
}

class _CountingHydrator extends ChatMessageHydrator {
  _CountingHydrator({
    required super.config,
    required super.remote,
    required super.mediaCache,
  });

  final List<String> hydratedIds = [];

  @override
  Future<List<ChatMessage>> hydrateAll(
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) async {
    hydratedIds.addAll(messages.map((message) => message.id));
    return messages
        .map((message) => message.copyWith(mediaUrls: ['cached:${message.id}']))
        .toList(growable: false);
  }
}

class _FakeUserRealtime extends UserRealtimeDataSource {
  _FakeUserRealtime()
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
