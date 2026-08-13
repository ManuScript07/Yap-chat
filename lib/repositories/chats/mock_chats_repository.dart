import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/abstract_chats_repository.dart';

/// In-memory репозиторий для разработки UI, Storybook-сценариев и тестов.
class MockChatsRepository implements IChatsRepository {
  MockChatsRepository()
    : _chats = [
        Chat(
          id: '1',
          userName: 'Алексей Иванов',
          lastMessage: 'Привет! Как дела?',
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
          unreadCount: 2,
          isOnline: true,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
        Chat(
          id: '2',
          userName: 'Марина Петрова',
          lastMessage: 'Завтра в силе?',
          lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
          unreadCount: 0,
          isOnline: false,
          isLastMessageFromMe: true,
          isMuted: true,
        ),
        Chat(
          id: '3',
          userName: 'Разработка Групп',
          lastMessage: 'Скиньте отчет по проекту до конца дня, пожалуйста.',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
          unreadCount: 15,
          isOnline: true,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
        Chat(
          id: '4',
          userName: 'Игорь С.',
          lastMessage: 'Ок, договорились',
          lastMessageTime: DateTime(2026, 7, 6, 12, 0),
          unreadCount: 0,
          isOnline: false,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
        Chat(
          id: '5',
          userName: 'Служба поддержки',
          lastMessage: 'Ваш запрос №12345 был успешно обработан.',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 4)),
          unreadCount: 0,
          isOnline: true,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
        Chat(
          id: '6',
          userName: 'Служба поддержки 2',
          lastMessage: 'Ваш запрос №12346 был успешно обработан.',
          lastMessageTime: DateTime(2026, 1, 7, 12, 0),
          unreadCount: 0,
          isOnline: true,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
        Chat(
          id: '7',
          userName: 'Служба поддержки 3',
          lastMessage: 'Ваш запрос №12347 был успешно обработан.',
          lastMessageTime: DateTime(2025, 7, 6, 12, 0),
          unreadCount: 0,
          isOnline: true,
          isLastMessageFromMe: false,
          isMuted: false,
        ),
      ];

  final List<Chat> _chats;

  static const _networkDelay = Duration(milliseconds: 0);

  @override
  Future<List<Chat>> getChats() async {
    await Future<void>.delayed(_networkDelay);
    return List.unmodifiable(_chats);
  }

  @override
  Future<void> deleteChats(Set<String> ids) async {
    await Future<void>.delayed(_networkDelay);
    _chats.removeWhere((chat) => ids.contains(chat.id));
  }

  @override
  Future<void> markAsRead(Set<String> ids) async {
    await Future<void>.delayed(_networkDelay);
    _replaceSelected(ids, (chat) => chat.copyWith(unreadCount: 0));
  }

  @override
  Future<void> toggleMute(Set<String> ids) async {
    await Future<void>.delayed(_networkDelay);
    _replaceSelected(ids, (chat) => chat.copyWith(isMuted: !chat.isMuted));
  }

  void _replaceSelected(Set<String> ids, Chat Function(Chat chat) update) {
    for (var index = 0; index < _chats.length; index++) {
      final chat = _chats[index];
      if (ids.contains(chat.id)) {
        _chats[index] = update(chat);
      }
    }
  }
}
