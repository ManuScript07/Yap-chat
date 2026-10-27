import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';

part 'chats_list_cache.dart';
part 'chats_available_cache.dart';

class ChatsCacheDataSource {
  static const _idBatchSize = 400;
  static const _deletedAccountDisplayName = 'Удалённый пользователь';
  const ChatsCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
    MediaCacheService? mediaCache,
  }) : _database = database,
       _userIdProvider = userIdProvider,
       _mediaCache = mediaCache;

  final AppDatabase _database;
  final String Function() _userIdProvider;
  final MediaCacheService? _mediaCache;

  Future<void> _prepareAvatarPaths() async {
    try {
      await _mediaCache?.prepareLocalPaths();
    } catch (_) {
      // A missing OS cache directory must not hide cached chat metadata.
    }
  }

  Stream<List<Chat>> watch({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    final pathsReady = _prepareAvatarPaths();
    return query.watch().asyncMap((rows) async {
      await pathsReady;
      return List.unmodifiable(rows.map(_mapRow));
    });
  }

  Future<List<Chat>> read({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where((table) => table.ownerUserId.equals(owner))
      ..orderBy([(table) => OrderingTerm.desc(table.lastMessageTime)]);
    final pathsReady = _prepareAvatarPaths();
    final rows = await query.get();
    await pathsReady;
    return rows.map(_mapRow).toList(growable: false);
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
    await _prepareAvatarPaths();
    return row == null ? null : _mapRow(row);
  }

  Future<Chat?> readById(String chatId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row =
        await (_database.select(_database.cachedChats)..where(
              (table) =>
                  table.ownerUserId.equals(owner) & table.id.equals(chatId),
            ))
            .getSingleOrNull();
    await _prepareAvatarPaths();
    return row == null ? null : _mapRow(row);
  }

  Stream<Chat?> watchById(String chatId, {String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where(
        (table) => table.ownerUserId.equals(owner) & table.id.equals(chatId),
      );
    final pathsReady = _prepareAvatarPaths();
    return query.watchSingleOrNull().asyncMap((row) async {
      await pathsReady;
      return row == null ? null : _mapRow(row);
    });
  }

  Stream<Chat?> watchByPeerId(String peerId, {String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.cachedChats)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) & table.peerId.equals(peerId),
      )
      ..limit(1);
    final pathsReady = _prepareAvatarPaths();
    return query.watchSingleOrNull().asyncMap((row) async {
      await pathsReady;
      return row == null ? null : _mapRow(row);
    }).distinct();
  }

  Future<bool> isDeliveryBlocked(String chatId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row =
        await (_database.select(_database.cachedChats)..where(
              (table) =>
                  table.ownerUserId.equals(owner) & table.id.equals(chatId),
            ))
            .getSingleOrNull();
    // Global bans deliberately remain server-authoritative: an administrator
    // may revoke one while this device is offline. Personal blocks, however,
    // are cached explicitly so a blocked sender never emits a network request.
    return row != null &&
        (row.blockedByMe || row.blockedByPeer || _isDeletedAccountRow(row));
  }

  Future<bool> replaceAll(List<Chat> chats, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _prepareAvatarPaths();
    final cached = await (_database.select(
      _database.cachedChats,
    )..where((t) => t.ownerUserId.equals(owner))).get();
    final cachedById = {for (final row in cached) row.id: row};
    if (cached.length == chats.length &&
        chats.every((chat) {
          final previous = cachedById[chat.id];
          return previous != null &&
              _sameChat(_mapRow(previous), chat) &&
              previous.listOrderMicros == _effectiveListOrder(chat, null);
        })) {
      return false;
    }

    await _database.transaction(() async {
      final ids = chats.map((chat) => chat.id).toSet();
      await remove(cachedById.keys.toSet().difference(ids), ownerUserId: owner);
      for (final chat in chats) {
        final previous = cachedById[chat.id];
        if (previous != null &&
            _sameChat(_mapRow(previous), chat) &&
            previous.listOrderMicros == _effectiveListOrder(chat, null)) {
          continue;
        }
        await _database
            .into(_database.cachedChats)
            .insertOnConflictUpdate(_companion(chat, owner));
      }
    });
    return true;
  }

  /// An authoritative response for ONLY [requestedIds]. Missing requested rows
  /// are hidden/inaccessible; rows outside the batch are never removed.
  Future<void> applySummaryBatch(
    Set<String> requestedIds,
    List<Chat> chats, {
    String? ownerUserId,
    Map<String, DateTime> activityByChatId = const {},
  }) async {
    final returnedIds = chats.map((chat) => chat.id).toSet();
    if (returnedIds.length != chats.length ||
        !requestedIds.containsAll(returnedIds) ||
        !returnedIds.containsAll(activityByChatId.keys)) {
      throw ArgumentError(
        'Summary response contains unrequested or duplicate IDs',
      );
    }
    if (requestedIds.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      final current = {
        for (final chat in await _readRowsForAction(
          requestedIds,
          ownerUserId: owner,
        ))
          chat.id: chat,
      };
      final removed = requestedIds.difference(returnedIds);
      if (removed.isNotEmpty) {
        await remove(removed, ownerUserId: owner);
      }
      for (final chat in chats) {
        final previous = current[chat.id];
        if (previous != null &&
            _sameChat(_mapRow(previous), chat) &&
            previous.listOrderMicros ==
                _effectiveListOrder(chat, activityByChatId[chat.id])) {
          continue;
        }
        await _database
            .into(_database.cachedChats)
            .insertOnConflictUpdate(
              _companion(chat, owner, activityByChatId[chat.id]),
            );
      }
      await _applyListActivity(chats, activityByChatId, owner);
    });
  }

  int _effectiveListOrder(Chat chat, DateTime? activityAt) {
    final preview = chat.lastMessageTime.microsecondsSinceEpoch;
    final activity = activityAt?.microsecondsSinceEpoch ?? preview;
    return preview > activity ? preview : activity;
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
        left.isMuted == right.isMuted &&
        left.blockedByMe == right.blockedByMe &&
        left.blockedByPeer == right.blockedByPeer &&
        left.peerIsGloballyBanned == right.peerIsGloballyBanned &&
        left.peerIsDeleted == right.peerIsDeleted;
  }

  Future<void> remove(Set<String> ids, {String? ownerUserId}) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    final orderedIds = ids.toList(growable: false);
    await _database.transaction(() async {
      for (var start = 0; start < orderedIds.length; start += _idBatchSize) {
        final batch = orderedIds.skip(start).take(_idBatchSize);
        await (_database.delete(_database.cachedChatListEntries)..where(
              (table) =>
                  table.ownerUserId.equals(owner) & table.chatId.isIn(batch),
            ))
            .go();
        await (_database.delete(_database.cachedChats)..where(
              (table) => table.ownerUserId.equals(owner) & table.id.isIn(batch),
            ))
            .go();
      }
    });
  }

  Future<List<Chat>> readForAction(
    Set<String> ids, {
    String? ownerUserId,
  }) async {
    return (await _readRowsForAction(
      ids,
      ownerUserId: ownerUserId,
    )).map(_mapRow).toList(growable: false);
  }

  Future<List<CachedChat>> _readRowsForAction(
    Set<String> ids, {
    String? ownerUserId,
  }) async {
    if (ids.isEmpty) return const [];
    final owner = ownerUserId ?? _userIdProvider();
    final chats = <CachedChat>[];
    final orderedIds = ids.toList(growable: false);
    for (var start = 0; start < orderedIds.length; start += _idBatchSize) {
      final batch = orderedIds.skip(start).take(_idBatchSize);
      final rows = await _database
          .customSelect(
            '''
        WITH requested(id) AS (VALUES ${List.filled(batch.length, '(?)').join(',')})
        SELECT c.* FROM requested r CROSS JOIN cached_chats c
        WHERE c.owner_user_id=? AND c.id=r.id
      ''',
            variables: [
              ...batch.map(Variable<String>.new),
              Variable<String>(owner),
            ],
            readsFrom: {_database.cachedChats},
          )
          .get();
      chats.addAll(rows.map((r) => _database.cachedChats.map(r.data)));
    }
    return chats;
  }

  Future<void> markAsReadIfUnchanged(
    List<Chat> snapshot, {
    String? ownerUserId,
  }) async {
    final expected = snapshot.where((chat) => chat.unreadCount > 0).toList();
    if (expected.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.update(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(owner) &
              table.id.isIn(expected.map((chat) => chat.id)) &
              expected
                  .map(
                    (chat) =>
                        table.id.equals(chat.id) &
                        table.unreadCount.equals(chat.unreadCount) &
                        table.lastMessageTime.equals(chat.lastMessageTime) &
                        table.lastMessage.equals(chat.lastMessage) &
                        (chat.lastMessageId == null
                            ? table.lastMessageId.isNull()
                            : table.lastMessageId.equals(chat.lastMessageId!)),
                  )
                  .reduce((left, right) => left | right),
        ))
        .write(const CachedChatsCompanion(unreadCount: Value(0)));
  }

  Future<Set<String>> readIdsWithMuteState(
    Set<String> ids, {
    required bool isMuted,
    String? ownerUserId,
  }) async {
    if (ids.isEmpty) return const {};
    final owner = ownerUserId ?? _userIdProvider();
    final table = _database.cachedChats;
    final query = _database.selectOnly(table)
      ..addColumns([table.id])
      ..where(
        table.ownerUserId.equals(owner) &
            table.id.isIn(ids) &
            table.isMuted.equals(isMuted),
      );
    return (await query.get()).map((row) => row.read(table.id)!).toSet();
  }

  Future<void> setMuted(
    Set<String> ids, {
    required bool isMuted,
    String? ownerUserId,
  }) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.update(_database.cachedChats)..where(
          (table) =>
              table.ownerUserId.equals(owner) &
              table.id.isIn(ids) &
              table.isMuted.equals(!isMuted),
        ))
        .write(CachedChatsCompanion(isMuted: Value(isMuted)));
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
            listOrderMicros: Value(message.timestamp.microsecondsSinceEpoch),
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
      cachedAvatarPath:
          row.blockedByPeer ||
              row.peerIsGloballyBanned ||
              _isDeletedAccountRow(row)
          ? null
          : _localAvatarPath(row),
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
      blockedByMe: row.blockedByMe,
      blockedByPeer: row.blockedByPeer,
      peerIsGloballyBanned: row.peerIsGloballyBanned,
      peerIsDeleted: _isDeletedAccountRow(row),
    );
  }

  String? _localAvatarPath(CachedChat row) {
    final storage = row.peerAvatarStoragePath;
    final url = row.peerAvatarUrl;
    if (storage?.isNotEmpty == true) {
      return _mediaCache?.localStorageFilePath(
        ownerUserId: row.ownerUserId,
        bucket: 'avatars',
        storagePath: storage!,
        mimeType: 'image/jpeg',
      );
    }
    return url?.isNotEmpty == true
        ? _mediaCache?.localStorageFilePath(
            ownerUserId: row.ownerUserId,
            bucket: MediaCacheService.externalAvatarsBucket,
            storagePath: url!,
          )
        : null;
  }

  CachedChatsCompanion _companion(
    Chat chat, [
    String? ownerUserId,
    DateTime? activityAt,
  ]) {
    return CachedChatsCompanion.insert(
      ownerUserId: ownerUserId ?? _userIdProvider(),
      id: chat.id,
      peerId: chat.peerId,
      peerUsername: chat.peerUsername,
      peerDisplayName: chat.userName,
      peerDisplayNameSearch: Value(chat.userName.toLowerCase()),
      peerAvatarUrl: Value(chat.avatarUrl),
      peerAvatarStoragePath: Value(chat.avatarStoragePath),
      lastMessageId: Value(chat.lastMessageId),
      lastMessage: chat.lastMessage,
      lastMessageType: chat.lastMessageType.name,
      lastMessageTime: chat.lastMessageTime,
      listOrderMicros: Value(_effectiveListOrder(chat, activityAt)),
      unreadCount: chat.unreadCount,
      isLastMessageFromMe: chat.isLastMessageFromMe,
      isMuted: chat.isMuted,
      lastSeenAt: Value(chat.lastSeenAt),
      showsLastSeen: Value(chat.showsLastSeen),
      blockedByMe: Value(chat.blockedByMe),
      blockedByPeer: Value(chat.blockedByPeer),
      peerIsGloballyBanned: Value(chat.peerIsGloballyBanned),
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

  bool _isDeletedAccountRow(CachedChat row) =>
      row.peerDisplayName == _deletedAccountDisplayName &&
      row.peerUsername.isEmpty &&
      row.peerAvatarUrl == null &&
      row.peerAvatarStoragePath == null;
}
