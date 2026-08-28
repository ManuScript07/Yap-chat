abstract interface class ILocalMediaRepository {
  /// Копирует внешний файл в постоянную директорию приложения.
  Future<String?> persistMedia(String sourcePath);

  /// Возвращает список путей к недавно использованным медиафайлам.
  List<String> getRecentMediaPaths();

  /// Удаляет только запись из списка последних медиа.
  /// Сам файл сохраняется, потому что он может использоваться сообщением.
  Future<void> deleteMedia(String path);

  /// Сохраняет фото для восстановления после пересоздания Activity.
  Future<void> savePendingMedia(String path);

  /// Возвращает и очищает восстановленное фото.
  Future<String?> consumePendingMedia();

  /// Сохраняет чат, из которого была открыта камера.
  Future<void> savePendingChatId(String chatId);

  /// Возвращает и очищает чат, ожидающий восстановления.
  Future<String?> consumePendingChatId();

  /// Очищает контекст камеры после обычного возврата.
  Future<void> clearPendingChatId();

  /// Удаляет локальные оригиналы и служебные ключи конкретного аккаунта.
  Future<void> clearUser(String ownerUserId);

  /// Удаляет только те оригиналы, на которые больше никто не ссылается.
  Future<void> collectGarbage();
}
