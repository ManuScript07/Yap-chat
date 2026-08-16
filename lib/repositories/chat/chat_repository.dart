import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';
import 'package:yap_chat/repositories/chat/mock_chat_repository.dart';

/// Production-адаптер репозитория чата.
///
/// Как и в модуле chats, эта реализация делегирует работу мок-источнику,
/// пока не подключен реальный backend-клиент.
class ChatRepository implements IChatRepository {
  ChatRepository({required AppConfig config})
    : _config = config,
      _fallback = MockChatRepository();

  final AppConfig _config;
  final MockChatRepository _fallback;

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    _config.talker.debug('ChatRepository.getMessagesStream: $chatId');
    return _fallback.getMessagesStream(chatId);
  }

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) {
    _config.talker.debug('ChatRepository.sendMessage to $chatId: $text');
    return _fallback.sendMessage(
      chatId,
      text,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  }) {
    _config.talker.debug(
      'ChatRepository.sendImages to $chatId: ${imagePaths.length} items',
    );
    return _fallback.sendImages(
      chatId,
      imagePaths,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) {
    _config.talker.debug('ChatRepository.sendAudio to $chatId');
    return _fallback.sendAudio(
      chatId,
      audioPath,
      duration,
      waveform,
      replyToMessageId: replyToMessageId,
    );
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
    double longitude, {
    String? replyToMessageId,
  }) {
    _config.talker.debug('ChatRepository.sendLocation to $chatId');
    return _fallback.sendLocation(
      chatId,
      latitude,
      longitude,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  }) {
    _config.talker.debug('ChatRepository.deleteMessage: $messageId');
    return _fallback.deleteMessage(
      chatId,
      messageId,
      deleteForEveryone: deleteForEveryone,
    );
  }
}
