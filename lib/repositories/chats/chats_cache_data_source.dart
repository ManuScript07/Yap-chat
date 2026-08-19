import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
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

  Future<void> replaceAll(List<Chat> chats) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.cachedChats,
      )..where((table) => table.ownerUserId.equals(_userIdProvider()))).go();
      for (final chat in chats) {
        await _database.into(_database.cachedChats).insert(_companion(chat));
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

  Chat _mapRow(CachedChat row) {
    return Chat(
      id: row.id,
      peerId: row.peerId,
      peerUsername: row.peerUsername,
      userName: row.peerDisplayName,
      avatarUrl: row.peerAvatarUrl,
      avatarStoragePath: row.peerAvatarStoragePath,
      lastMessage: row.lastMessage,
      lastMessageType: ChatPreviewType.values.byName(row.lastMessageType),
      lastMessageTime: row.lastMessageTime,
      unreadCount: row.unreadCount,
      isOnline: false,
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
      lastMessage: chat.lastMessage,
      lastMessageType: chat.lastMessageType.name,
      lastMessageTime: chat.lastMessageTime,
      unreadCount: chat.unreadCount,
      isLastMessageFromMe: chat.isLastMessageFromMe,
      isMuted: chat.isMuted,
      cachedAt: DateTime.now().toUtc(),
    );
  }
}
