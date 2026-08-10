import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/chat/chat.dart';
import 'package:yap_chat/features/chats/chats.dart';

/// Контейнер репозиториев приложения.
///
/// Он хранит только абстрактные контракты, а выбор конкретных реализаций
/// делается фабриками [prod] и [dev].
class RepositoryContainer {
  const RepositoryContainer({
    required this.chatsRepository,
    required this.chatRepository,
  });

  factory RepositoryContainer.prod({
    required AppConfig config,
  }) {
    return RepositoryContainer(
      chatsRepository: ChatsRepository(config: config),
      chatRepository: ChatRepository(config: config),
    );
  }

  factory RepositoryContainer.dev({
    required AppConfig config,
  }) {
    return RepositoryContainer(
      chatsRepository: MockChatsRepository(),
      chatRepository: MockChatRepository(),
    );
  }

  final IChatsRepository chatsRepository;
  final IChatRepository chatRepository;
}
