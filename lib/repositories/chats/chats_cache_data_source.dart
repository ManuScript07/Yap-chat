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

  Stream<List<Chat>> watch({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    return query.watch().map((rows) => List.unmodifiable(rows.map(_mapRow)));
  }

  Future<List<Chat>> read({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    return (await query.get()).map(_mapRow).toList(growable: false);
  }

  Future<Chat?> readByPeerId(String peerId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) & table.peerId.equals(peerId),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  Future<bool> isDeliveryBlocked(
    String chatId, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row = await (_database.select(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(owner) & table.id.equals(chatId),
        ))
        .getSingleOrNull();
    // A globally banned peer uses an intentionally generic cached identity.
    // Do not turn that presentation cache into a permanent local-only send
    // state: the server remains authoritative and rejects a real global ban,
    // while an administrator's unban can recover immediately after sync.
    return row != null &&
        row.peerUsername.isEmpty &&
        row.peerDisplayName != _globallyBannedDisplayName;
  }

  Future<bool> replaceAll(List<Chat> chats, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final cachedChats = await read(ownerUserId: owner);
    if (_sameChats(cachedChats, chats)) return false;

    await _database.transaction(() async {
      final ids = chats.map((chat) => chat.id).toSet();
      final deleteQuery = _database.delete(_database.cachedChats)
        ..where(
          (table) =>
              table.ownerUserId.equals(owner) &
              (ids.isEmpty ? const Constant(true) : table.id.isNotIn(ids)),
        );
      await deleteQuery.go();
      for (final chat in chats) {
        await _database
            .into(_database.cachedChats)
            .insertOnConflictUpdate(_companion(chat, owner));
      }
    });
    return true;
  }

  bool _sameChats(List<Chat> cached, List<Chat> incoming) {
    if (cached.length != incoming.length) return false;
    final cachedById = {for (final chat in cached) chat.id: chat};
    return incoming.every((chat) {
      final current = cachedById[chat.id];
      return current != null && _sameChat(current, chat);
    });
  }

  bool _sameChat(Chat left, Chat right) {
    bool sameSecond(DateTime? first, DateTime? second) {
      if (first == null || second == null) return first == second;
      return first.millisecondsSinceEpoch ~/ 1000 ==
          second.millisecondsSinceEpoch ~/ 1000;
    }

    return left.id == right.id &&
        left.peerId == right.peerId &&
        left.peerUsername == right.peerUsername &&
        left.userName == right.userName &&
        left.avatarUrl == right.avatarUrl &&
        left.avatarStoragePath == right.avatarStoragePath &&
        left.lastMessageId == right.lastMessageId &&
        left.lastMessage == right.lastMessage &&
        left.lastMessageType == right.lastMessageType &&
        sameSecond(left.lastMessageTime, right.lastMessageTime) &&
        left.unreadCount == right.unreadCount &&
        sameSecond(left.lastSeenAt, right.lastSeenAt) &&
        left.showsLastSeen == right.showsLastSeen &&
        left.isLastMessageFromMe == right.isLastMessageFromMe &&
        left.isMuted == right.isMuted;
  }

  Future<void> remove(Set<String> ids, {String? ownerUserId}) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.delete(_database.cachedChats)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.isIn(ids),
        ))
        .go();
  }

  Future<void> markAsRead(Set<String> ids, {String? ownerUserId}) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.update(_database.cachedChats)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.isIn(ids),
        ))
        .write(const CachedChatsCompanion(unreadCount: Value(0)));
  }

  Future<void> toggleMute(Set<String> ids, {String? ownerUserId}) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    final rows =
        await (_database.select(_database.cachedChats)..where(
              (table) => table.ownerUserId.equals(owner) & table.id.isIn(ids),
            ))
            .get();
    await _database.transaction(() async {
      for (final row in rows) {
        await (_database.update(_database.cachedChats)..where(
              (table) =>
                  table.ownerUserId.equals(owner) & table.id.equals(row.id),
            ))
            .write(CachedChatsCompanion(isMuted: Value(!row.isMuted)));
      }
    });
  }

  Future<void> updateLastMessage(
    ChatMessage message, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.update(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(owner) & table.id.equals(message.chatId),
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
      blockedByPeer: row.peerUsername.isEmpty,
      // The generic display name is server-produced only for a global ban.
      // It is persisted with the ordinary chat cache, so offline startup does
      // not need a separate status request.
      peerIsGloballyBanned:
          row.peerDisplayName == _globallyBannedDisplayName,
    );
  }

  CachedChatsCompanion _companion(Chat chat, [String? ownerUserId]) {
    return CachedChatsCompanion.insert(
      ownerUserId: ownerUserId ?? _userIdProvider(),
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

  static const _globallyBannedDisplayName = 'Заблокированный пользователь';
}
