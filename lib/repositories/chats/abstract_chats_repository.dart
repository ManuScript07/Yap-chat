import 'package:yap_chat/features/chats/data/data.dart';

abstract interface class IChatsRepository {
  /// Cache-first поток, который автоматически синхронизируется с сервером.
  Stream<List<Chat>> watchChats();

  /// Cache-only поток одного чата без создания дополнительного Realtime-канала.
  Stream<Chat?> watchChat(String chatId);

  /// Загружает полный список чатов из источника данных.
  Future<List<Chat>> getChats();

  /// Cache-first lookup; a miss reads that conversation only on a supported server.
  Future<Chat?> getChatById(String chatId);

  /// Returns an existing direct chat from the local cache only.
  /// It never starts a network synchronization.
  Future<Chat?> getCachedChatByPeerId(String peerId);

  /// Возвращает локальный путь к аватару, скачивая его только при cache miss.
  Future<String?> resolveAvatar(Chat chat);

  /// Возвращает существующий direct-чат или локальный черновик без записи в БД.
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  });

  /// Возвращает существующий direct-чат или создаёт его при первой отправке.
  Future<Chat> ensureDirectChat(String peerId);

  /// Удаляет выбранные чаты по их идентификаторам.
  Future<void> deleteChats(Set<String> ids);

  /// Сбрасывает счетчик непрочитанных сообщений у выбранных чатов.
  Future<void> markAsRead(Set<String> ids);

  /// Sets one explicit mute state. Already matching cached rows need no write.
  Future<void> setMuted(Set<String> ids, {required bool isMuted});

  /// Останавливает Realtime-канал, сохраняя локальную подписку на кеш.
  Future<void> pauseRealtime();

  /// Пересоздаёт Realtime-канал и сразу сверяет кеш с сервером.
  Future<void> resumeRealtime();
}

/// Optional read capability while presentation adapters migrate away from
/// complete list snapshots. Production implements indexed, account-scoped reads.
abstract interface class IChatsPeerRepository {
  Stream<Chat?> watchChatByPeerId(String peerId);
}

/// Confirmed account-wide count, independent of list/search coverage. Null
/// means no confirmed snapshot (including servers awaiting the migration).
abstract interface class IChatsUnreadRepository {
  Stream<int?> watchUnreadCount();
}

extension ChatsPeerRepositoryAccess on IChatsRepository {
  IChatsPeerRepository get _peerRepository => this as IChatsPeerRepository;
  Stream<Chat?> watchChatByPeerId(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) return Stream.value(null);
    final repository = this;
    if (repository is IChatsPeerRepository) {
      return _peerRepository.watchChatByPeerId(normalized);
    }
    // Legacy/in-memory implementations retain their existing contract. Never
    // turn a cache observer into a getChats()/network call.
    return watchChats().map((chats) {
      for (final chat in chats) {
        if (chat.peerId == normalized) return chat;
      }
      return null;
    }).distinct();
  }
}
