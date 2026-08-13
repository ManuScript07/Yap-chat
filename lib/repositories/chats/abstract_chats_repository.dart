import 'package:yap_chat/features/chats/data/data.dart';

abstract interface class IChatsRepository {
  /// Загружает полный список чатов из источника данных.
  Future<List<Chat>> getChats();

  /// Удаляет выбранные чаты по их идентификаторам.
  Future<void> deleteChats(Set<String> ids);

  /// Сбрасывает счетчик непрочитанных сообщений у выбранных чатов.
  Future<void> markAsRead(Set<String> ids);

  /// Переключает mute-состояние у выбранных чатов.
  Future<void> toggleMute(Set<String> ids);
}
