import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/app/chat_navigation_coordinator.dart';
import 'package:yap_chat/features/chats/data/data.dart';

void main() {
  final chats = <Chat>[_chat('first'), _chat('second')];

  test('opens a queued chat only once', () async {
    final openedChatIds = <String>[];
    final coordinator = ChatNavigationCoordinator(
      loadChat: (chatId) async => _findChat(chats, chatId),
      navigateToChat: (chat) async => openedChatIds.add(chat.id),
      isConversationVisible: (_) => false,
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await Future.wait([
      coordinator.openById('first'),
      coordinator.openById('first'),
    ]);

    expect(openedChatIds, ['first']);
  });

  test('does not navigate to an already visible chat', () async {
    var loaded = false;
    final coordinator = ChatNavigationCoordinator(
      loadChat: (chatId) async {
        loaded = true;
        return _findChat(chats, chatId);
      },
      navigateToChat: (_) async {},
      isConversationVisible: (chatId) => chatId == 'first',
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await coordinator.openById('first');

    expect(loaded, isFalse);
  });

  test('serializes competing chat opens', () async {
    final openedChatIds = <String>[];
    final coordinator = ChatNavigationCoordinator(
      loadChat: (chatId) async => _findChat(chats, chatId),
      navigateToChat: (chat) async => openedChatIds.add(chat.id),
      isConversationVisible: (_) => false,
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await Future.wait([
      coordinator.openById('first'),
      coordinator.openById('second'),
    ]);

    expect(openedChatIds, ['first', 'second']);
  });

  test('opens a chat from the list without looking it up', () async {
    var wasLookedUp = false;
    final openedChatIds = <String>[];
    final coordinator = ChatNavigationCoordinator(
      loadChat: (chatId) async {
        wasLookedUp = true;
        return _findChat(chats, chatId);
      },
      navigateToChat: (chat) async => openedChatIds.add(chat.id),
      isConversationVisible: (_) => false,
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await coordinator.open(chats.first);

    expect(openedChatIds, ['first']);
    expect(wasLookedUp, isFalse);
  });
}

Chat? _findChat(List<Chat> chats, String chatId) {
  for (final chat in chats) {
    if (chat.id == chatId) return chat;
  }
  return null;
}

Chat _chat(String id) => Chat(
  id: id,
  userName: id,
  lastMessage: '',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);
