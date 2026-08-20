import 'package:yap_chat/features/chat/data/data.dart';

abstract interface class IChatRepository {
  /// Подписка на поток сообщений конкретного чата.
  Stream<List<ChatMessage>> getMessagesStream(String chatId);

  /// Загружает следующую страницу более старых сообщений.
  Future<bool> loadMoreMessages(String chatId);

  /// Отправка сообщения в чат.
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  });

  /// Отправка изображений в чат.
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  });

  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  });

  /// Повторная отправка медиа-сообщения после ошибки.
  Future<void> retryImages(String chatId, ChatMessage message);

  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude, {
    String? replyToMessageId,
  });

  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  });

  /// Немедленно синхронизирует все чаты, открытые в текущем дереве UI.
  Future<void> synchronizeOpenChats();

  /// Приостанавливает фоновые повторы отправки до возвращения приложения.
  Future<void> pauseNetwork();
}
