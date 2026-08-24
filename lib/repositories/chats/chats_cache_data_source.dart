import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';

class ChatsCacheDataSource {
  const ChatsCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
  }) : _database = database,
       _userIdProvider = userIdProvider;

  final AppDatabase _database;
  final String Function() _userIdProvider;

  Stream<List<Chat>> watch() {
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(_userIdProvider()))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    return query.watch().map((rows) => List.unmodifiable(rows.map(_mapRow)));
  }

  Future<List<Chat>> read() async {
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(_userIdProvider()))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    return (await query.get()).map(_mapRow).toList(growable: false);
  }

  Future<Chat?> readByPeerId(String peerId) async {
    final query = _database.select(_database.cachedChats)
      ..where(
        (table) =>
            table.ownerUserId.equals(_userIdProvider()) &
            table.peerId.equals(peerId),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  Future<void> replaceAll(List<Chat> chats) async {
    await _database.transaction(() async {
      final ownerUserId = _userIdProvider();
      final ids = chats.map((chat) => chat.id).toSet();
      final deleteQuery = _database.delete(_database.cachedChats)
        ..where(
          (table) =>
              table.ownerUserId.equals(ownerUserId) &
              (ids.isEmpty ? const Constant(true) : table.id.isNotIn(ids)),
        );
      await deleteQuery.go();
      for (final chat in chats) {
        await _database
            .into(_database.cachedChats)
            .insertOnConflictUpdate(_companion(chat));
      }
    });
  }

  Future<void> remove(Set<String> ids) async {
    if (ids.isEmpty) return;
    await (_database.delete(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.isIn(ids),
        ))
        .go();
  }

  Future<void> markAsRead(Set<String> ids) async {
    if (ids.isEmpty) return;
    await (_database.update(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.isIn(ids),
        ))
        .write(const CachedChatsCompanion(unreadCount: Value(0)));
  }

  Future<void> toggleMute(Set<String> ids) async {
    if (ids.isEmpty) return;
    final rows =
        await (_database.select(_database.cachedChats)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.id.isIn(ids),
            ))
            .get();
    await _database.transaction(() async {
      for (final row in rows) {
        await (_database.update(_database.cachedChats)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.id.equals(row.id),
            ))
            .write(CachedChatsCompanion(isMuted: Value(!row.isMuted)));
      }
    });
  }

  Future<void> updateLastMessage(ChatMessage message) async {
    await (_database.update(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) &
              table.id.equals(message.chatId),
        ))
        .write(
          CachedChatsCompanion(
            lastMessageId: Value(message.id),
            lastMessage: Value(message.text),
            lastMessageType: Value(_previewType(message.type).name),
            lastMessageTime: Value(message.timestamp),
            isLastMessageFromMe: Value(message.isMine),
          ),
        );
  }

  Chat _mapRow(CachedChat row) {
    return Chat(
      id: row.id,
      peerId: row.peerId,
      peerUsername: row.peerUsername,
      userName: row.peerDisplayName,
      avatarUrl: row.peerAvatarUrl,
      avatarStoragePath: row.peerAvatarStoragePath,
      lastMessageId: row.lastMessageId,
      lastMessage: row.lastMessage,
      lastMessageType: ChatPreviewType.values.byName(row.lastMessageType),
      lastMessageTime: row.lastMessageTime,
      unreadCount: row.unreadCount,
      isOnline: false,
      lastSeenAt: row.lastSeenAt,
      showsLastSeen: row.showsLastSeen,
      isLastMessageFromMe: row.isLastMessageFromMe,
      isMuted: row.isMuted,
    );
  }

  CachedChatsCompanion _companion(Chat chat) {
    return CachedChatsCompanion.insert(
      ownerUserId: _userIdProvider(),
      id: chat.id,
      peerId: chat.peerId,
      peerUsername: chat.peerUsername,
      peerDisplayName: chat.userName,
      peerAvatarUrl: Value(chat.avatarUrl),
      peerAvatarStoragePath: Value(chat.avatarStoragePath),
      lastMessageId: Value(chat.lastMessageId),
      lastMessage: chat.lastMessage,
      lastMessageType: chat.lastMessageType.name,
      lastMessageTime: chat.lastMessageTime,
      unreadCount: chat.unreadCount,
      isLastMessageFromMe: chat.isLastMessageFromMe,
      isMuted: chat.isMuted,
      lastSeenAt: Value(chat.lastSeenAt),
      showsLastSeen: Value(chat.showsLastSeen),
      cachedAt: DateTime.now().toUtc(),
    );
  }

  ChatPreviewType _previewType(MessageType type) {
    return switch (type) {
      MessageType.image => ChatPreviewType.image,
      MessageType.audio => ChatPreviewType.audio,
      MessageType.location => ChatPreviewType.location,
      MessageType.text => ChatPreviewType.text,
    };
  }
}
