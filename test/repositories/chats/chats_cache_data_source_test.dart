import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';

void main() {
  test('isolates cached chats between signed-in users', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var currentUserId = 'first-user';
    final cache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => currentUserId,
    );

    await cache.replaceAll([_chat('first-chat')]);
    currentUserId = 'second-user';
    await cache.replaceAll([_chat('second-chat')]);

    final secondChat = (await cache.read()).single;
    expect(secondChat.id, 'second-chat');
    expect(secondChat.lastMessageId, 'message-second-chat');
    expect(
      secondChat.lastSeenAt?.isAtSameMomentAs(DateTime.utc(2026, 8, 19, 12)),
      isTrue,
    );
    expect(secondChat.showsLastSeen, isTrue);
    currentUserId = 'first-user';
    expect((await cache.read()).single.id, 'first-chat');
  });

  test(
    'an explicit owner cannot be redirected by a later account switch',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      var currentUserId = 'account-a';
      final cache = ChatsCacheDataSource(
        database: database,
        userIdProvider: () => currentUserId,
      );

      const capturedOwner = 'account-a';
      currentUserId = 'account-b';
      await cache.replaceAll([
        _chat('late-account-a-chat'),
      ], ownerUserId: capturedOwner);

      expect(await cache.read(ownerUserId: 'account-b'), isEmpty);
      expect(
        (await cache.read(ownerUserId: 'account-a')).single.id,
        'late-account-a-chat',
      );
    },
  );

  test('updates chat preview from the cached latest message', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'first-user';
    final cache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => userId,
    );
    final timestamp = DateTime.utc(2026, 8, 20, 12);
    await cache.replaceAll([_chat('chat-id')]);

    await cache.updateLastMessage(
      ChatMessage(
        id: 'pending-message',
        chatId: 'chat-id',
        senderId: userId,
        text: 'Pending text',
        timestamp: timestamp,
        isMine: true,
        status: MessageStatus.sending,
      ),
    );

    final chat = (await cache.read()).single;
    expect(chat.lastMessageId, 'pending-message');
    expect(chat.lastMessage, 'Pending text');
    expect(chat.lastMessageTime.isAtSameMomentAs(timestamp), isTrue);
    expect(chat.isLastMessageFromMe, isTrue);
  });

  test('finds a cached direct chat by peer for the signed-in user', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var currentUserId = 'first-user';
    final cache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => currentUserId,
    );

    await cache.replaceAll([_chat('first-chat')]);
    currentUserId = 'second-user';
    await cache.replaceAll([_chat('second-chat')]);

    expect(await cache.readByPeerId('peer-first-chat'), isNull);
    expect((await cache.readByPeerId('peer-second-chat'))?.id, 'second-chat');
  });

  test(
    'uses explicit block flags instead of an empty username for delivery',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const userId = 'first-user';
      final cache = ChatsCacheDataSource(
        database: database,
        userIdProvider: () => userId,
      );

      final ordinaryChat = _chat('ordinary').copyWith(peerUsername: '');
      await cache.replaceAll([ordinaryChat]);
      expect(await cache.isDeliveryBlocked('ordinary'), isFalse);

      await cache.replaceAll([ordinaryChat.copyWith(blockedByPeer: true)]);
      expect(await cache.isDeliveryBlocked('ordinary'), isTrue);
    },
  );

  test('clears conversation history but keeps pending deletion', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'first-user';
    final cache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => userId,
    );
    final clearedAt = DateTime.utc(2026, 8, 20, 12);

    await cache.upsertMessage(
      ChatMessage(
        id: 'message-id',
        chatId: 'chat-id',
        senderId: 'peer-id',
        text: '',
        timestamp: clearedAt.subtract(const Duration(minutes: 1)),
        isMine: false,
        type: MessageType.image,
        mediaUrls: const ['local-image'],
        mediaStoragePaths: const ['chat-id/peer-id/message-id/0.jpg'],
      ),
    );
    await cache.putPendingChatDeletion(
      id: 'deletion-id',
      chatId: 'chat-id',
      clearedAt: clearedAt,
    );

    final files = await cache.clearConversations({'chat-id'});

    expect(await cache.readMessages('chat-id', currentUserId: userId), isEmpty);
    expect(files.imageStoragePaths, {'chat-id/peer-id/message-id/0.jpg'});
    expect((await cache.readPendingChatDeletions()).single.id, 'deletion-id');
    expect(await cache.readPendingOperations(), isEmpty);
  });

  test('keeps message order stable when timestamps are equal', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'first-user';
    final cache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => userId,
    );
    final timestamp = DateTime.utc(2026, 8, 20, 12);

    await cache.upsertMessages([
      _message(id: 'message-a', timestamp: timestamp),
      _message(id: 'message-b', timestamp: timestamp),
    ]);

    final messages = await cache.readMessages('chat-id', currentUserId: userId);

    expect(messages.map((message) => message.id), ['message-b', 'message-a']);
  });

  test('skips identical chat rows but persists a changed preview', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'first-user';
    final cache = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => userId,
    );
    final initial = _chat('chat-id');

    expect(await cache.replaceAll([initial]), isTrue);
    expect(await cache.replaceAll([initial]), isFalse);

    final changed = initial.copyWith(
      lastMessageId: 'new-message',
      lastMessage: 'New message',
      lastMessageTime: initial.lastMessageTime.add(const Duration(seconds: 1)),
    );
    expect(await cache.replaceAll([changed]), isTrue);
    expect((await cache.read()).single.lastMessageId, 'new-message');
  });

  test(
    'skips an identical refresh but keeps new messages realtime-safe',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const userId = 'first-user';
      final cache = ChatCacheDataSource(
        database: database,
        userIdProvider: () => userId,
      );
      final older = _message(
        id: 'older',
        timestamp: DateTime.utc(2026, 8, 20, 12, 0, 0, 450),
      );

      expect(await cache.replaceRecentMessages('chat-id', [older]), isTrue);
      final restoredOlder = (await cache.readMessages(
        'chat-id',
        currentUserId: userId,
      )).single;
      // Cursor pagination now preserves server microseconds instead of
      // intentionally rounding message creation times to whole seconds.
      expect(
        restoredOlder,
        older.copyWith(timestamp: older.timestamp.toLocal()),
      );
      expect(await cache.replaceRecentMessages('chat-id', [older]), isFalse);

      final newer = _message(
        id: 'newer',
        timestamp: DateTime.utc(2026, 8, 20, 12, 0, 1, 125),
      );
      expect(
        await cache.replaceRecentMessages('chat-id', [newer, older]),
        isTrue,
      );
      expect(
        (await cache.readMessages(
          'chat-id',
          currentUserId: userId,
        )).map((message) => message.id),
        ['newer', 'older'],
      );
    },
  );
}

Chat _chat(String id) {
  return Chat(
    id: id,
    peerId: 'peer-$id',
    peerUsername: 'username',
    userName: 'User',
    lastMessageId: 'message-$id',
    lastMessage: 'Message',
    lastMessageTime: DateTime.utc(2026, 8, 19),
    unreadCount: 1,
    isOnline: false,
    lastSeenAt: DateTime.utc(2026, 8, 19, 12),
    isLastMessageFromMe: false,
  );
}

ChatMessage _message({required String id, required DateTime timestamp}) {
  return ChatMessage(
    id: id,
    chatId: 'chat-id',
    senderId: 'peer-id',
    text: id,
    timestamp: timestamp,
    isMine: false,
  );
}
