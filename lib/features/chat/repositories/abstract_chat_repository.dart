import 'package:yap_chat/features/chat/data/data.dart';

abstract interface class IChatRepository {
  /// Подписка на поток сообщений конкретного чата.
  Stream<List<ChatMessage>> getMessagesStream(String chatId);

  /// Отправка сообщения в чат.
  Future<void> sendMessage(String chatId, String text);
}
