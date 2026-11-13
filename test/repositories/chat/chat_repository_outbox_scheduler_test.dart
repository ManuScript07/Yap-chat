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

void main() {
  test(
    'retries a closed chat on foreground and preserves its message id',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = AccountSessionController(initialUserId: 'owner');
      final remote = _ControlledChatRemote([StateError('offline'), null]);
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
      var clock = DateTime.utc(2026, 9, 7, 12);
      final config = AppConfig(
        environment: AppEnvironment.local,
        preferences: preferences,
        talker: Talker(),
        env: const {},
        database: database,
        accountSessionController: account,
      );
      final sync = ConversationSyncService(
        cache: chatCache,
        remote: remote,
        hydrator: ChatMessageHydrator(
          config: config,
          remote: remote,
          mediaCache: mediaCache,
        ),
        chatsCache: chatsCache,
        accountSessionController: account,
      );
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
        now: () => clock,
      );
      addTearDown(repository.pauseNetwork);

      await repository.pauseNetwork();
      await repository.sendMessage('closed-chat', 'hello');
      expect(remote.sentIds, isEmpty);

      await repository.synchronizeOpenChats();
      await _waitUntil(() => remote.sentIds.length == 1);
      final firstId = remote.sentIds.single;
      final pendingAfterFailure = await chatCache.readPendingOperation(firstId);
      expect(pendingAfterFailure, isNotNull);
      expect(pendingAfterFailure!.attempts, 1);
      expect(pendingAfterFailure.nextAttemptAt, isNotNull);

      clock = clock.add(const Duration(seconds: 10));
      await repository.synchronizeOpenChats();
      await _waitUntil(() => remote.sentIds.length == 2);

      expect(remote.sentIds, [firstId, firstId]);
      expect(await chatCache.readPendingOperation(firstId), isNull);
      final message = await chatCache.readMessage(
        firstId,
        currentUserId: 'owner',
      );
      expect(message?.status, MessageStatus.sent);
    },
  );

  test('arms its own retry timer for a closed chat', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final account = AccountSessionController(initialUserId: 'owner');
    final remote = _ControlledChatRemote([StateError('offline'), null]);
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
    final sync = ConversationSyncService(
      cache: chatCache,
      remote: remote,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: remote,
        mediaCache: mediaCache,
      ),
      chatsCache: chatsCache,
      accountSessionController: account,
    );
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
    );
    addTearDown(repository.pauseNetwork);

    await repository.sendMessage('closed-chat', 'hello');
    await _waitUntil(
      () => remote.sentIds.length == 2,
      timeout: const Duration(seconds: 8),
    );

    expect(remote.sentIds, hasLength(2));
    expect(remote.sentIds[1], remote.sentIds.first);
    expect(await chatCache.readPendingOperation(remote.sentIds.first), isNull);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for an asynchronous outbox operation');
}

class _ControlledChatRemote extends ChatRemoteDataSource {
  _ControlledChatRemote(this._outcomes)
    : super(client: SupabaseClient('http://localhost', 'test-key'));

  final List<Object?> _outcomes;
  final List<String> sentIds = [];

  @override
  Future<void> sendMessage({
    required String id,
    required String chatId,
    required MessageType type,
    String text = '',
    double? latitude,
    double? longitude,
    String? replyToMessageId,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    sentIds.add(id);
    final outcome = _outcomes.removeAt(0);
    if (outcome != null) throw outcome;
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
