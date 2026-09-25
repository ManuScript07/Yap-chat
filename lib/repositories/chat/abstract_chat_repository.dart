import 'package:yap_chat/features/chat/data/data.dart';

class ChatHistoryChange {
  const ChatHistoryChange.deleted(this.deletedMessageId) : reconnected = false;
  const ChatHistoryChange.reconnected()
    : deletedMessageId = null,
      reconnected = true;

  final String? deletedMessageId;
  final bool reconnected;
}

abstract interface class IChatRepository {
  /// Подписка на поток сообщений конкретного чата.
  Stream<List<ChatMessage>> getMessagesStream(String chatId);

  /// Загружает следующую страницу более старых сообщений.
  Future<bool> loadMoreMessages(String chatId);

  /// Reads a separate, bounded history window around a visible message.
  /// These rows must not be inserted into the contiguous recent-message cache.
  Future<List<ChatMessage>> loadMessageWindow(String chatId, String messageId);

  Future<List<ChatMessage>> loadWindowOlder(String chatId, ChatMessage oldest);

  Future<List<ChatMessage>> loadWindowNewer(String chatId, ChatMessage newest);

  /// Hydrates media only when a focused-history row enters the viewport.
  Future<ChatMessage> hydrateWindowMedia(ChatMessage message);

  /// Uses the existing user Realtime channel; no per-chat channel is added.
  Stream<ChatHistoryChange> watchHistoryChanges(String chatId);

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

  /// Requeues a terminally failed outgoing message for a fresh delivery run.
  Future<void> retryMessage(String chatId, ChatMessage message);

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
