import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_remote_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_repository.dart';

void main() {
  test(
    'shares list synchronization and does not hydrate closed conversations',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = AccountSessionController(initialUserId: 'owner');
      final mediaCache = MediaCacheService(database: database);
      addTearDown(mediaCache.dispose);
      final chatsRemote = _FakeChatsRemote(chats: [_chat('one'), _chat('two')]);
      final chatRemote = _FakeChatRemote();
      final chatCache = ChatCacheDataSource(
        database: database,
        userIdProvider: () => account.userId!,
      );
      final chatsCache = ChatsCacheDataSource(
        database: database,
        userIdProvider: () => account.userId!,
      );
      final sync = ConversationSyncService(
        cache: chatCache,
        remote: chatRemote,
        hydrator: ChatMessageHydrator(
          config: AppConfig(
            environment: AppEnvironment.prod,
            preferences: preferences,
            talker: Talker(),
            env: const {},
            database: database,
            accountSessionController: account,
          ),
          remote: chatRemote,
          mediaCache: mediaCache,
        ),
        chatsCache: chatsCache,
        accountSessionController: account,
      );
      final repository = ChatsRepository(
        config: AppConfig(
          environment: AppEnvironment.prod,
          preferences: preferences,
          talker: Talker(),
          env: const {},
          database: database,
          accountSessionController: account,
        ),
        cache: chatsCache,
        remote: chatsRemote,
        mediaCache: mediaCache,
        chatCache: chatCache,
        conversationSync: sync,
        accountSessionController: account,
      );

      final firstLoaded = Completer<void>();
      final firstSubscription = repository.watchChats().listen((chats) {
        if (chats.length == 2 && !firstLoaded.isCompleted) {
          firstLoaded.complete();
        }
      });
      await firstLoaded.future.timeout(const Duration(seconds: 2));

      final secondLoaded = Completer<void>();
      final secondSubscription = repository.watchChats().listen((chats) {
        if (chats.length == 2 && !secondLoaded.isCompleted) {
          secondLoaded.complete();
        }
      });
      await secondLoaded.future.timeout(const Duration(seconds: 2));

      expect(chatsRemote.fetchCalls, 1);
      expect(chatRemote.fetchCalls, 0);

      chatsRemote.emit(
        const ConversationChange(
          conversationId: 'one',
          reason: 'reaction_changed',
          messageId: 'historical-message',
          reactionState: MessageReactionState(
            version: 1,
            reactions: [
              MessageReaction(userId: 'peer', code: ReactionCode.heart),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        chatsRemote.fetchCalls,
        1,
        reason: 'A reaction must not refresh chat summaries',
      );
      expect(
        chatRemote.fetchCalls,
        0,
        reason: 'A reaction must not load history',
      );
      expect(
        (await chatCache.readReactionState(
          'historical-message',
          ownerUserId: 'owner',
        )).version,
        1,
      );
      expect(
        await chatCache.readMessages('one', currentUserId: 'owner'),
        isEmpty,
      );

      chatsRemote.emit(
        const ConversationChange(conversationId: 'one', reason: 'insert'),
      );
      chatsRemote.emit(
        const ConversationChange(conversationId: 'two', reason: 'insert'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(chatsRemote.fetchCalls, 2);
      expect(chatRemote.fetchCalls, 0);

      sync.openConversation('one');
      chatsRemote.emit(
        const ConversationChange(conversationId: 'one', reason: 'muted'),
      );
      chatsRemote.emit(
        const ConversationChange(conversationId: 'two', reason: 'muted'),
      );
      await _waitUntil(() => chatsRemote.fetchCalls == 3);
      expect(
        chatsRemote.fetchCalls,
        3,
        reason: 'One coalesced metadata refresh',
      );
      expect(
        chatRemote.fetchCalls,
        0,
        reason: 'Mute must not reload open history',
      );
      sync.closeConversation('one');

      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await chatsRemote.dispose();
    },
  );

  test('rebinds the shared watcher after an account switch', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final account = AccountSessionController(initialUserId: 'owner-a');
    final mediaCache = MediaCacheService(database: database);
    addTearDown(mediaCache.dispose);
    final chatsRemote = _FakeChatsRemote(chats: [_chat('owner-a-chat')]);
    final chatRemote = _FakeChatRemote();
    final chatCache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final chatsCache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => account.userId!,
    );
    final repository = _repository(
      preferences: preferences,
      database: database,
      account: account,
      mediaCache: mediaCache,
      chatsCache: chatsCache,
      chatCache: chatCache,
      chatsRemote: chatsRemote,
      chatRemote: chatRemote,
    );

    final receivedIds = <String>[];
    final subscription = repository.watchChats().listen(
      (chats) => receivedIds.addAll(chats.map((chat) => chat.id)),
    );
    await _waitUntil(() => receivedIds.contains('owner-a-chat'));

    account.setAuthenticatedUser(null);
    account.setAuthenticatedUser('owner-b');
    chatsRemote.chats = [_chat('owner-b-chat')];
    await repository.pauseRealtime();
    await repository.resumeRealtime();
    await _waitUntil(() => receivedIds.contains('owner-b-chat'));

    expect(
      (await chatsCache.read(ownerUserId: 'owner-a')).single.id,
      'owner-a-chat',
    );
    expect(
      (await chatsCache.read(ownerUserId: 'owner-b')).single.id,
      'owner-b-chat',
    );

    await subscription.cancel();
    await chatsRemote.dispose();
  });

  test(
    'opens a draft without waiting for a stalled initial summary sync',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = AccountSessionController(initialUserId: 'owner');
      final mediaCache = MediaCacheService(database: database);
      addTearDown(mediaCache.dispose);
      final stalledFetch = Completer<List<Chat>>();
      final chatsRemote = _FakeChatsRemote(chats: [_chat('existing')])
        ..stalledFetch = stalledFetch;
      final chatRemote = _FakeChatRemote();
      final chatCache = ChatCacheDataSource(
        database: database,
        userIdProvider: () => account.userId!,
      );
      final chatsCache = ChatsCacheDataSource(
        database: database,
        userIdProvider: () => account.userId!,
      );
      final repository = _repository(
        preferences: preferences,
        database: database,
        account: account,
        mediaCache: mediaCache,
        chatsCache: chatsCache,
        chatCache: chatCache,
        chatsRemote: chatsRemote,
        chatRemote: chatRemote,
      );
      final subscription = repository.watchChats().listen(
        (_) {},
        onError: (_, _) {},
      );
      await _waitUntil(() => chatsRemote.fetchCalls == 1);

      final watch = Stopwatch()..start();
      final draft = await repository.prepareDirectChat(
        peerId: 'peer-existing',
        peerUsername: 'peer',
        peerDisplayName: 'Peer',
      );

      expect(draft.isDraft, isTrue);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(chatsRemote.fetchCalls, 1);

      stalledFetch.complete(chatsRemote.chats);
      await subscription.cancel();
      await chatsRemote.dispose();
    },
  );
}

ChatsRepository _repository({
  required SharedPreferences preferences,
  required AppDatabase database,
  required AccountSessionController account,
  required MediaCacheService mediaCache,
  required ChatsCacheDataSource chatsCache,
  required ChatCacheDataSource chatCache,
  required _FakeChatsRemote chatsRemote,
  required _FakeChatRemote chatRemote,
}) {
  final config = AppConfig(
    environment: AppEnvironment.prod,
    preferences: preferences,
    talker: Talker(),
    env: const {},
    database: database,
    accountSessionController: account,
  );
  return ChatsRepository(
    config: config,
    cache: chatsCache,
    remote: chatsRemote,
    mediaCache: mediaCache,
    chatCache: chatCache,
    conversationSync: ConversationSyncService(
      cache: chatCache,
      remote: chatRemote,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: chatRemote,
        mediaCache: mediaCache,
      ),
      chatsCache: chatsCache,
      accountSessionController: account,
    ),
    accountSessionController: account,
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the expected cache state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeChatsRemote extends ChatsRemoteDataSource {
  _FakeChatsRemote({required this.chats})
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );

  List<Chat> chats;
  final StreamController<ConversationChange> _changes =
      StreamController<ConversationChange>.broadcast();
  int fetchCalls = 0;
  Completer<List<Chat>>? stalledFetch;

  @override
  Future<List<Chat>> fetchChats() async {
    fetchCalls++;
    final stalled = stalledFetch;
    if (stalled != null) return stalled.future;
    return chats;
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async =>
      (await fetchChats()).where((chat) => ids.contains(chat.id)).toList();

  @override
  Stream<ConversationChange> watchChanges() => _changes.stream;

  void emit(ConversationChange change) => _changes.add(change);

  Future<void> dispose() => _changes.close();
}

class _FakeChatRemote extends ChatRemoteDataSource {
  _FakeChatRemote()
    : super(client: SupabaseClient('http://localhost', 'test-key'));

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

Chat _chat(String id) {
  return Chat(
    id: id,
    peerId: 'peer-$id',
    peerUsername: 'peer$id',
    userName: 'Peer $id',
    lastMessageId: 'message-$id',
    lastMessage: 'Last message',
    lastMessageTime: DateTime.utc(2026, 9, 6),
    unreadCount: 0,
    isOnline: false,
    isLastMessageFromMe: false,
  );
}
