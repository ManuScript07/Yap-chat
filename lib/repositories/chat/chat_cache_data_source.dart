import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';

class ChatCacheDataSource {
  static const pendingChatDeletionType = 'hide_conversation';

  const ChatCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
  }) : _database = database,
       _userIdProvider = userIdProvider;

  final AppDatabase _database;
  final String Function() _userIdProvider;

  Stream<List<ChatMessage>> watchMessages(
    String chatId, {
    required String currentUserId,
  }) {
    final query = _database.select(_database.cachedMessages)
      ..where(
        (table) =>
            table.ownerUserId.equals(_userIdProvider()) &
            table.chatId.equals(chatId),
      )
      ..orderBy([(table) => OrderingTerm.desc(table.timestamp)]);
    return query.watch().map(
      (rows) =>
          List.unmodifiable(rows.map((row) => _mapMessage(row, currentUserId))),
    );
  }

  Future<List<ChatMessage>> readMessages(
    String chatId, {
    required String currentUserId,
  }) async {
    final query = _database.select(_database.cachedMessages)
      ..where(
        (table) =>
            table.ownerUserId.equals(_userIdProvider()) &
            table.chatId.equals(chatId),
      )
      ..orderBy([(table) => OrderingTerm.desc(table.timestamp)]);
    return (await query.get())
        .map((row) => _mapMessage(row, currentUserId))
        .toList(growable: false);
  }

  Future<ChatMessage?> readMessage(
    String id, {
    required String currentUserId,
  }) async {
    final row =
        await (_database.select(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapMessage(row, currentUserId);
  }

  Future<void> replaceRecentMessages(
    String chatId,
    List<ChatMessage> messages,
  ) async {
    await _database.transaction(() async {
      if (messages.isEmpty) {
        await (_database.delete(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.chatId.equals(chatId) &
                  table.isPending.not(),
            ))
            .go();
      } else {
        final oldest = messages.last.timestamp;
        final ids = messages.map((message) => message.id).toSet();
        await (_database.delete(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.chatId.equals(chatId) &
                  table.isPending.not() &
                  table.timestamp.isBiggerOrEqualValue(oldest) &
                  table.id.isNotIn(ids),
            ))
            .go();
      }
      await _upsertMessages(messages);
    });
  }

  Future<void> upsertMessages(List<ChatMessage> messages) {
    return _database.transaction(() => _upsertMessages(messages));
  }

  Future<void> upsertMessage(ChatMessage message, {bool isPending = false}) {
    return _database
        .into(_database.cachedMessages)
        .insertOnConflictUpdate(
          _messageCompanion(message, isPending: isPending),
        );
  }

  Future<void> markMessageStatus(String id, MessageStatus status) async {
    await (_database.update(_database.cachedMessages)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.equals(id),
        ))
        .write(
          CachedMessagesCompanion(
            status: Value(status.name),
            isPending: Value(
              status == MessageStatus.sending || status == MessageStatus.error,
            ),
          ),
        );
  }

  Future<void> removeMessage(String id) async {
    await (_database.delete(_database.cachedMessages)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.equals(id),
        ))
        .go();
  }

  Future<void> putPendingOperation(PendingMessageOperation operation) {
    return _database
        .into(_database.pendingChatOperations)
        .insertOnConflictUpdate(
          PendingChatOperationsCompanion.insert(
            ownerUserId: _userIdProvider(),
            id: operation.id,
            chatId: operation.chatId,
            type: operation.type,
            payloadJson: jsonEncode(operation.payload),
            attempts: Value(operation.attempts),
            lastError: Value(operation.lastError),
            createdAt: operation.createdAt,
          ),
        );
  }

  Future<List<PendingMessageOperation>> readPendingOperations() async {
    final query = _database.select(_database.pendingChatOperations)
      ..where(
        (table) =>
            table.ownerUserId.equals(_userIdProvider()) &
            table.type.isIn(MessageType.values.map((type) => type.name)),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return (await query.get())
        .map(
          (row) => PendingMessageOperation(
            id: row.id,
            chatId: row.chatId,
            type: row.type,
            payload: Map<String, dynamic>.from(
              jsonDecode(row.payloadJson) as Map,
            ),
            attempts: row.attempts,
            lastError: row.lastError,
            createdAt: row.createdAt,
          ),
        )
        .toList(growable: false);
  }

  Future<void> markPendingFailure(String id, Object error) async {
    final row =
        await (_database.select(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(_userIdProvider()) &
                  table.id.equals(id),
            ))
            .getSingleOrNull();
    if (row == null) return;
    await (_database.update(_database.pendingChatOperations)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.equals(id),
        ))
        .write(
          PendingChatOperationsCompanion(
            attempts: Value(row.attempts + 1),
            lastError: Value(error.toString()),
          ),
        );
  }

  Future<void> removePendingOperation(String id) async {
    await (_database.delete(_database.pendingChatOperations)..where(
          (table) =>
              table.ownerUserId.equals(_userIdProvider()) & table.id.equals(id),
        ))
        .go();
  }

  Future<void> putPendingChatDeletion({
    required String id,
    required String chatId,
    required DateTime clearedAt,
  }) {
    return _database
        .into(_database.pendingChatOperations)
        .insertOnConflictUpdate(
          PendingChatOperationsCompanion.insert(
            ownerUserId: _userIdProvider(),
            id: id,
            chatId: chatId,
            type: pendingChatDeletionType,
            payloadJson: jsonEncode({
              'cleared_at': clearedAt.toUtc().toIso8601String(),
            }),
            createdAt: clearedAt.toUtc(),
          ),
        );
  }

  Future<List<PendingChatDeletion>> readPendingChatDeletions() async {
    final query = _database.select(_database.pendingChatOperations)
      ..where(
        (table) =>
            table.ownerUserId.equals(_userIdProvider()) &
            table.type.equals(pendingChatDeletionType),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return (await query.get())
        .map((row) {
          final payload = Map<String, dynamic>.from(
            jsonDecode(row.payloadJson) as Map,
          );
          return PendingChatDeletion(
            id: row.id,
            chatId: row.chatId,
            clearedAt:
                DateTime.tryParse(
                  payload['cleared_at'] as String? ?? '',
                )?.toUtc() ??
                row.createdAt.toUtc(),
          );
        })
        .toList(growable: false);
  }

  Future<ConversationCacheFiles> clearConversations(Set<String> chatIds) async {
    if (chatIds.isEmpty) return const ConversationCacheFiles();
    final ownerUserId = _userIdProvider();
    final messageRows =
        await (_database.select(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) &
                  table.chatId.isIn(chatIds),
            ))
            .get();
    final pendingRows =
        await (_database.select(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(ownerUserId) &
                  table.chatId.isIn(chatIds) &
                  table.type.equals(pendingChatDeletionType).not(),
            ))
            .get();

    final imageStoragePaths = <String>{};
    final audioStoragePaths = <String>{};
    for (final row in messageRows) {
      imageStoragePaths.addAll(
        List<String>.from(jsonDecode(row.mediaStoragePathsJson) as List),
      );
      final audioStoragePath = row.audioStoragePath;
      if (audioStoragePath != null) audioStoragePaths.add(audioStoragePath);
    }
    final outboxAudioPaths = <String>{};
    for (final row in pendingRows) {
      final payload = jsonDecode(row.payloadJson);
      if (payload is! Map) continue;
      final audioPath = payload['audio_path'];
      if (audioPath is String && audioPath.isNotEmpty) {
        outboxAudioPaths.add(audioPath);
      }
    }

    await _database.transaction(() async {
      await (_database.delete(_database.cachedMessages)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId) &
                table.chatId.isIn(chatIds),
          ))
          .go();
      await (_database.delete(_database.pendingChatOperations)..where(
            (table) =>
                table.ownerUserId.equals(ownerUserId) &
                table.chatId.isIn(chatIds) &
                table.type.equals(pendingChatDeletionType).not(),
          ))
          .go();
    });
    return ConversationCacheFiles(
      imageStoragePaths: imageStoragePaths,
      audioStoragePaths: audioStoragePaths,
      outboxAudioPaths: outboxAudioPaths,
    );
  }

  Future<void> _upsertMessages(List<ChatMessage> messages) async {
    for (final message in messages) {
      await _database
          .into(_database.cachedMessages)
          .insertOnConflictUpdate(_messageCompanion(message));
    }
  }

  CachedMessagesCompanion _messageCompanion(
    ChatMessage message, {
    bool isPending = false,
  }) {
    final reply = message.replyTo;
    return CachedMessagesCompanion.insert(
      ownerUserId: _userIdProvider(),
      id: message.id,
      chatId: message.chatId,
      senderId: message.senderId,
      messageText: message.text,
      timestamp: message.timestamp,
      status: message.status.name,
      type: message.type.name,
      mediaUrlsJson: jsonEncode(message.mediaUrls),
      mediaStoragePathsJson: jsonEncode(message.mediaStoragePaths),
      latitude: Value(message.latitude),
      longitude: Value(message.longitude),
      audioUrl: Value(message.audioUrl),
      audioStoragePath: Value(message.audioStoragePath),
      audioDurationMs: Value(message.audioDuration?.inMilliseconds),
      audioWaveformJson: jsonEncode(message.audioWaveform),
      replyMessageId: Value(reply?.messageId),
      replySenderId: Value(reply?.senderId),
      replyType: Value(reply?.type.name),
      replyText: Value(reply?.text),
      readAt: Value(message.readAt),
      isPending: isPending,
      cachedAt: DateTime.now().toUtc(),
    );
  }

  ChatMessage _mapMessage(CachedMessage row, String currentUserId) {
    final replyType = row.replyType;
    final reply = row.replyMessageId == null || replyType == null
        ? null
        : MessageReply(
            messageId: row.replyMessageId!,
            senderId: row.replySenderId ?? '',
            isMine: row.replySenderId == currentUserId,
            type: MessageType.values.byName(replyType),
            text: row.replyText ?? '',
          );
    return ChatMessage(
      id: row.id,
      chatId: row.chatId,
      senderId: row.senderId,
      text: row.messageText,
      timestamp: row.timestamp,
      isMine: row.senderId == currentUserId,
      status: MessageStatus.values.byName(row.status),
      type: MessageType.values.byName(row.type),
      mediaUrls: List<String>.from(jsonDecode(row.mediaUrlsJson) as List),
      mediaStoragePaths: List<String>.from(
        jsonDecode(row.mediaStoragePathsJson) as List,
      ),
      latitude: row.latitude,
      longitude: row.longitude,
      audioUrl: row.audioUrl,
      audioStoragePath: row.audioStoragePath,
      audioDuration: row.audioDurationMs == null
          ? null
          : Duration(milliseconds: row.audioDurationMs!),
      audioWaveform: (jsonDecode(row.audioWaveformJson) as List)
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      replyTo: reply,
      readAt: row.readAt,
    );
  }
}

class PendingMessageOperation {
  const PendingMessageOperation({
    required this.id,
    required this.chatId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String chatId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
}

class PendingChatDeletion {
  const PendingChatDeletion({
    required this.id,
    required this.chatId,
    required this.clearedAt,
  });

  final String id;
  final String chatId;
  final DateTime clearedAt;
}

class ConversationCacheFiles {
  const ConversationCacheFiles({
    this.imageStoragePaths = const {},
    this.audioStoragePaths = const {},
    this.outboxAudioPaths = const {},
  });

  final Set<String> imageStoragePaths;
  final Set<String> audioStoragePaths;
  final Set<String> outboxAudioPaths;
}
