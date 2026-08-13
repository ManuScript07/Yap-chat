import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';
import 'package:yap_chat/repositories/chat/mock_chat_repository.dart';

/// Production-адаптер репозитория чата.
///
/// Как и в модуле chats, эта реализация делегирует работу мок-источнику,
/// пока не подключен реальный backend-клиент.
class ChatRepository implements IChatRepository {
  ChatRepository({
    required AppConfig config,
  })  : _config = config,
        _fallback = MockChatRepository();

  final AppConfig _config;
  final MockChatRepository _fallback;

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    _config.talker.debug('ChatRepository.getMessagesStream: $chatId');
    return _fallback.getMessagesStream(chatId);
  }

  @override
  Future<void> sendMessage(String chatId, String text) {
    _config.talker.debug('ChatRepository.sendMessage to $chatId: $text');
    return _fallback.sendMessage(chatId, text);
  }

  @override
  Future<void> sendImages(String chatId, List<String> imagePaths) {
    _config.talker.debug('ChatRepository.sendImages to $chatId: ${imagePaths.length} items');
    return _fallback.sendImages(chatId, imagePaths);
  }

  @override
  Future<void> retryImages(String chatId, ChatMessage message) {
    _config.talker.debug('ChatRepository.retryImages: ${message.id}');
    return _fallback.retryImages(chatId, message);
  }

  @override
  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude,
  ) {
    _config.talker.debug('ChatRepository.sendLocation to $chatId');
    return _fallback.sendLocation(chatId, latitude, longitude);
  }
}
