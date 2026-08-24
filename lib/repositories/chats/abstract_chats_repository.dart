import 'package:yap_chat/features/chats/data/data.dart';

abstract interface class IChatsRepository {
  /// Cache-first поток, который автоматически синхронизируется с сервером.
  Stream<List<Chat>> watchChats();

  /// Загружает полный список чатов из источника данных.
  Future<List<Chat>> getChats();

  Future<Chat?> getChatById(String chatId);

  /// Возвращает существующий direct-чат или создаёт его для пользователя.
  Future<Chat> openDirectChat(String peerId);

  /// Удаляет выбранные чаты по их идентификаторам.
  Future<void> deleteChats(Set<String> ids);

  /// Сбрасывает счетчик непрочитанных сообщений у выбранных чатов.
  Future<void> markAsRead(Set<String> ids);

  /// Переключает mute-состояние у выбранных чатов.
  Future<void> toggleMute(Set<String> ids);

  /// Останавливает Realtime-канал, сохраняя локальную подписку на кеш.
  Future<void> pauseRealtime();

  /// Пересоздаёт Realtime-канал и сразу сверяет кеш с сервером.
  Future<void> resumeRealtime();
}
