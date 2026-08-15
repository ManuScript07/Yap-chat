import 'package:yap_chat/features/chat/data/data.dart';

abstract interface class IChatRepository {
  /// Подписка на поток сообщений конкретного чата.
  Stream<List<ChatMessage>> getMessagesStream(String chatId);

  /// Отправка сообщения в чат.
  Future<void> sendMessage(String chatId, String text);

  /// Отправка изображений в чат.
  Future<void> sendImages(String chatId, List<String> imagePaths);

  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform,
  );

  /// Повторная отправка медиа-сообщения после ошибки.
  Future<void> retryImages(String chatId, ChatMessage message);

  Future<void> sendLocation(String chatId, double latitude, double longitude);
}
