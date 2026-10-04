import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/pending_message_retry_policy.dart';

class ChatCacheDataSource {
  static const pendingChatDeletionType = 'hide_conversation';

  ChatCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
  }) : _database = database,
       _userIdProvider = userIdProvider;

  final AppDatabase _database;
  final String Function() _userIdProvider;
  // A response started before a deletion may arrive afterwards. Keep a small
  // process-local tombstone set so that response cannot reinsert the message.
  final Set<String> _removedMessageKeys = {};
  static const _maxRemovedMessageKeys = 512;

  String _messageKey(String ownerUserId, String id) => '$ownerUserId\u0000$id';

  void _rememberRemoved(String ownerUserId, Iterable<String> ids) {
    for (final id in ids) {
      final key = _messageKey(ownerUserId, id);
      _removedMessageKeys.remove(key);
      _removedMessageKeys.add(key);
    }
    while (_removedMessageKeys.length > _maxRemovedMessageKeys) {
      _removedMessageKeys.remove(_removedMessageKeys.first);
    }
  }

  Stream<List<ChatMessage>> watchMessages(
    String chatId, {
    required String currentUserId,
  }) {
    final table = _database.cachedMessages;
    final states = _database.cachedMessageReactionStates;
    final pending = _database.pendingMessageReactions;
    final query =
        _database.select(table).join([
            leftOuterJoin(
              states,
              states.ownerUserId.equalsExp(table.ownerUserId) &
                  states.messageId.equalsExp(table.id),
            ),
            leftOuterJoin(
              pending,
              pending.ownerUserId.equalsExp(table.ownerUserId) &
                  pending.messageId.equalsExp(table.id),
            ),
          ])
          ..where(
            table.ownerUserId.equals(currentUserId) &
                table.chatId.equals(chatId),
          )
          ..orderBy([
            OrderingTerm.desc(table.timestamp),
            OrderingTerm.desc(table.id),
          ]);
    return query
        .watch()
        .map(
        (rows) => List<ChatMessage>.unmodifiable(
            rows.map((row) {
              final confirmed = row.readTableOrNull(states);
              var state = confirmed == null
                  ? const MessageReactionState()
                  : MessageReactionState.fromJson(
                      jsonDecode(confirmed.stateJson),
                    );
              final intent = row.readTableOrNull(pending);
              if (intent != null) {
                state = state.withChoice(
                  currentUserId,
                  ReactionCode.parse(intent.code),
                );
              }
              return _mapMessage(
                row.readTable(table),
                currentUserId,
              ).copyWith(reactionState: state);
            }),
          ),
        )
        .distinct((before, after) {
          if (before.length != after.length) return false;
          for (var i = 0; i < before.length; i++) {
            if (before[i] != after[i]) return false;
          }
          return true;
        });
  }

  Future<MessageReactionState> readReactionState(
    String messageId, {
    required String ownerUserId,
    bool optimistic = true,
  }) async {
    final row =
        await (_database.select(_database.cachedMessageReactionStates)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.messageId.equals(messageId),
            ))
            .getSingleOrNull();
    var state = row == null
        ? const MessageReactionState()
        : MessageReactionState.fromJson(jsonDecode(row.stateJson));
    if (optimistic) {
      final pending = await readPendingReaction(
        messageId,
        ownerUserId: ownerUserId,
      );
      if (pending != null) {
        state = state.withChoice(ownerUserId, ReactionCode.parse(pending.code));
      }
    }
    return state;
  }

  Future<void> storeReactionState(
    String chatId,
    String messageId,
    MessageReactionState state, {
    required String ownerUserId,
  }) async {
    if (_removedMessageKeys.contains(_messageKey(ownerUserId, messageId))) {
      return;
    }
    final existing = await readReactionState(
      messageId,
      ownerUserId: ownerUserId,
      optimistic: false,
    );
    if (state.version < existing.version || state == existing) return;
    await _database
        .into(_database.cachedMessageReactionStates)
        .insertOnConflictUpdate(
          CachedMessageReactionStatesCompanion.insert(
            ownerUserId: ownerUserId,
            messageId: messageId,
            chatId: chatId,
            version: state.version,
            stateJson: jsonEncode(state.toJson()),
          ),
        );
  }

  Future<void> storeReactionStates(
    String chatId,
    Map<String, MessageReactionState> states, {
    required String ownerUserId,
  }) => _database.transaction(() async {
    for (final entry in states.entries) {
      await storeReactionState(
        chatId,
        entry.key,
        entry.value,
        ownerUserId: ownerUserId,
      );
    }
  });

  Future<List<ChatMessage>> mergeReactionStates(
    List<ChatMessage> messages, {
    required String ownerUserId,
  }) async {
    if (messages.isEmpty) return messages;
    final ids = messages.map((m) => m.id).toList();
    final rows =
        await (_database.select(_database.cachedMessageReactionStates)..where(
              (t) => t.ownerUserId.equals(ownerUserId) & t.messageId.isIn(ids),
            ))
            .get();
    final pending =
        await (_database.select(_database.pendingMessageReactions)..where(
              (t) => t.ownerUserId.equals(ownerUserId) & t.messageId.isIn(ids),
            ))
            .get();
    final confirmed = {
      for (final row in rows)
        row.messageId: MessageReactionState.fromJson(jsonDecode(row.stateJson)),
    };
    final intents = {for (final row in pending) row.messageId: row};
    return messages
        .map((message) {
          final cached = confirmed[message.id];
          var state =
              cached != null && cached.version >= message.reactionState.version
              ? cached
              : message.reactionState;
          final intent = intents[message.id];
          if (intent != null) {
            state = state.withChoice(
              ownerUserId,
              ReactionCode.parse(intent.code),
            );
          }
          return message.copyWith(reactionState: state);
        })
        .toList(growable: false);
  }

  Future<PendingMessageReaction?> readPendingReaction(
    String messageId, {
    required String ownerUserId,
  }) =>
      (_database.select(_database.pendingMessageReactions)..where(
            (t) =>
                t.ownerUserId.equals(ownerUserId) &
                t.messageId.equals(messageId),
          ))
          .getSingleOrNull();

  Future<void> enqueueReaction({
    required String ownerUserId,
    required String chatId,
    required String messageId,
    required String operationId,
    required ReactionCode? code,
    required int expectedRevision,
    required DateTime dueAt,
  }) => _database
      .into(_database.pendingMessageReactions)
      .insertOnConflictUpdate(
        PendingMessageReactionsCompanion.insert(
          ownerUserId: ownerUserId,
          messageId: messageId,
          chatId: chatId,
          operationId: operationId,
          code: Value(code?.wireName),
          expectedRevision: expectedRevision,
          nextAttemptAt: dueAt,
          attempts: const Value(0),
        ),
      );

  Future<List<PendingMessageReaction>> readReactionQueue(String ownerUserId) =>
      (_database.select(_database.pendingMessageReactions)
            ..where((t) => t.ownerUserId.equals(ownerUserId))
            ..orderBy([(t) => OrderingTerm.asc(t.nextAttemptAt)])
            ..limit(100))
          .get();

  Future<void> finishReactionOperation(PendingMessageReaction operation) =>
      (_database.delete(_database.pendingMessageReactions)..where(
            (t) =>
                t.ownerUserId.equals(operation.ownerUserId) &
                t.messageId.equals(operation.messageId) &
                t.operationId.equals(operation.operationId),
          ))
          .go();

  Future<void> deferReactionOperation(
    PendingMessageReaction operation,
    DateTime dueAt,
  ) =>
      (_database.update(_database.pendingMessageReactions)..where(
            (t) =>
                t.ownerUserId.equals(operation.ownerUserId) &
                t.messageId.equals(operation.messageId) &
                t.operationId.equals(operation.operationId),
          ))
          .write(
            PendingMessageReactionsCompanion(
              attempts: Value(operation.attempts + 1),
              nextAttemptAt: Value(dueAt),
            ),
          );

  Future<void> rebasePendingReaction(
    String messageId,
    String ownerUserId,
    int revision,
  ) =>
      (_database.update(_database.pendingMessageReactions)..where(
            (t) =>
                t.ownerUserId.equals(ownerUserId) &
                t.messageId.equals(messageId),
          ))
          .write(
            PendingMessageReactionsCompanion(expectedRevision: Value(revision)),
          );

  Future<void> removeReactionMetadata(
    String chatId,
    Set<String> ids, {
    required String ownerUserId,
  }) async {
    await (_database.delete(_database.cachedMessageReactionStates)..where(
          (t) =>
              t.ownerUserId.equals(ownerUserId) &
              t.chatId.equals(chatId) &
              t.messageId.isIn(ids),
        ))
        .go();
    await (_database.delete(_database.pendingMessageReactions)..where(
          (t) =>
              t.ownerUserId.equals(ownerUserId) &
              t.chatId.equals(chatId) &
              t.messageId.isIn(ids),
        ))
        .go();
  }

  Future<List<ChatMessage>> readMessages(
    String chatId, {
    required String currentUserId,
  }) async {
    final query = _database.select(_database.cachedMessages)
      ..where(
        (table) =>
            table.ownerUserId.equals(currentUserId) &
            table.chatId.equals(chatId),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.timestamp),
        (table) => OrderingTerm.desc(table.id),
      ]);
    return mergeReactionStates(
      (await query.get())
          .map((row) => _mapMessage(row, currentUserId))
          .toList(growable: false),
      ownerUserId: currentUserId,
    );
  }

  /// Reads only the currently displayed cache page. Pending and local-only
  /// messages have no server row to validate.
  Future<Set<String>> readServerMessageIds(
    String chatId, {
    required String currentUserId,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return const {};
    final table = _database.cachedMessages;
    final query = _database.selectOnly(table)
      ..addColumns([table.id])
      ..where(
        table.ownerUserId.equals(currentUserId) &
            table.chatId.equals(chatId) &
            table.isPending.not() &
            table.id.isIn(ids),
      );
    return (await query.get()).map((row) => row.read(table.id)!).toSet();
  }

  /// Returns only the newest cached message. Summary reconciliation only needs
  /// this row to preserve a local pending preview; reading the whole history
  /// for every chat makes that reconciliation proportional to cached history.
  Future<ChatMessage?> readLatestMessage(
    String chatId, {
    required String currentUserId,
  }) async {
    final query = _database.select(_database.cachedMessages)
      ..where(
        (table) =>
            table.ownerUserId.equals(currentUserId) &
            table.chatId.equals(chatId),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.timestamp),
        (table) => OrderingTerm.desc(table.id),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapMessage(row, currentUserId);
  }

  Future<ChatMessage?> readMessage(
    String id, {
    required String currentUserId,
  }) async {
    final row =
        await (_database.select(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(currentUserId) & table.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapMessage(row, currentUserId);
  }

  Future<bool> replaceRecentMessages(
    String chatId,
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      for (final message in messages) {
        await storeReactionState(
          chatId,
          message.id,
          message.reactionState,
          ownerUserId: owner,
        );
      }
    });
    if (await _recentMessagesMatch(chatId, messages, owner)) return false;

    await _database.transaction(() async {
      if (messages.isEmpty) {
        await (_database.delete(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.chatId.equals(chatId) &
                  table.isPending.not(),
            ))
            .go();
      } else {
        final oldest = messages.last.timestamp;
        final ids = messages.map((message) => message.id).toSet();
        await (_database.delete(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.chatId.equals(chatId) &
                  table.isPending.not() &
                  table.timestamp.isBiggerOrEqualValue(oldest) &
                  table.id.isNotIn(ids),
            ))
            .go();
      }
      await _upsertMessages(messages, owner);
    });
    return true;
  }

  Future<bool> _recentMessagesMatch(
    String chatId,
    List<ChatMessage> messages,
    String ownerUserId,
  ) async {
    final query = _database.select(_database.cachedMessages)
      ..where(
        (table) =>
            table.ownerUserId.equals(ownerUserId) &
            table.chatId.equals(chatId) &
            table.isPending.not() &
            (messages.isEmpty
                ? const Constant(true)
                : table.timestamp.isBiggerOrEqualValue(
                    _normalizeTimestamp(messages.last.timestamp),
                  )),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.timestamp),
        (table) => OrderingTerm.desc(table.id),
      ]);
    if (messages.isEmpty) query.limit(1);
    final rows = await query.get();
    if (rows.length != messages.length) return false;

    for (var index = 0; index < rows.length; index++) {
      final cached = _mapMessage(rows[index], ownerUserId);
      if (cached !=
          _normalizeMessageTimestamps(
            messages[index],
          ).copyWith(reactionState: const MessageReactionState())) {
        return false;
      }
    }
    return true;
  }

  ChatMessage _normalizeMessageTimestamps(ChatMessage message) {
    final readAt = message.readAt;
    return message.copyWith(
      timestamp: _normalizeTimestamp(message.timestamp),
      readAt: readAt == null ? null : _normalizeTimestamp(readAt),
      clearReadAt: readAt == null,
    );
  }

  DateTime _normalizeTimestamp(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        (value.millisecondsSinceEpoch ~/ 1000) * 1000,
      );

  Future<void> upsertMessages(
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    return _database.transaction(() => _upsertMessages(messages, owner));
  }

  Future<void> upsertMessage(
    ChatMessage message, {
    bool isPending = false,
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    if (_removedMessageKeys.contains(_messageKey(owner, message.id))) {
      return Future<void>.value();
    }
    return _database
        .into(_database.cachedMessages)
        .insertOnConflictUpdate(
          _messageCompanion(message, owner, isPending: isPending),
        );
  }

  Future<void> markMessageStatus(
    String id,
    MessageStatus status, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.update(_database.cachedMessages)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.equals(id),
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

  Future<void> removeMessage(String id, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    _rememberRemoved(owner, [id]);
    await (_database.delete(_database.cachedMessages)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.equals(id),
        ))
        .go();
  }

  /// Applies an authoritative server deletion for this conversation only.
  Future<void> removeMessages(
    String chatId,
    Set<String> ids, {
    String? ownerUserId,
  }) async {
    if (ids.isEmpty) return;
    final owner = ownerUserId ?? _userIdProvider();
    _rememberRemoved(owner, ids);
    await _database.transaction(() async {
      await removeReactionMetadata(chatId, ids, ownerUserId: owner);
      await (_database.delete(_database.cachedMessages)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.chatId.equals(chatId) &
                table.id.isIn(ids),
          ))
          .go();
      await (_database.update(_database.cachedMessages)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.chatId.equals(chatId) &
                table.replyMessageId.isIn(ids),
          ))
          .write(
            const CachedMessagesCompanion(
              replyMessageId: Value(null),
              replySenderId: Value(null),
              replyType: Value(null),
              replyText: Value(null),
            ),
          );
    });
  }

  Future<void> putPendingOperation(
    PendingMessageOperation operation, {
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    return _database
        .into(_database.pendingChatOperations)
        .insertOnConflictUpdate(
          PendingChatOperationsCompanion.insert(
            ownerUserId: owner,
            id: operation.id,
            chatId: operation.chatId,
            type: operation.type,
            payloadJson: jsonEncode(operation.payload),
            attempts: Value(operation.attempts),
            lastError: Value(operation.lastError),
            nextAttemptAt: Value(
              operation.nextAttemptAt ?? operation.createdAt,
            ),
            lastAttemptAt: Value(operation.lastAttemptAt),
            createdAt: operation.createdAt,
          ),
        );
  }

  Future<List<PendingMessageOperation>> readPendingOperations({
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.pendingChatOperations)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
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
            nextAttemptAt: row.nextAttemptAt?.toUtc(),
            lastAttemptAt: row.lastAttemptAt?.toUtc(),
            createdAt: row.createdAt.toUtc(),
          ),
        )
        .toList(growable: false);
  }

  /// Returns only operations which are both due and the oldest retryable
  /// operation for their conversation. This preserves message order within a
  /// chat without making an old offline chat block another chat's delivery.
  Future<List<PendingMessageOperation>> readDuePendingOperations({
    required DateTime dueAt,
    String? ownerUserId,
    int limit = 32,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final rows = await _database
        .customSelect(
          '''
        SELECT candidate.*
        FROM pending_chat_operations AS candidate
        WHERE candidate.owner_user_id = ?
          AND candidate.type IN ('text', 'image', 'audio', 'location')
          AND candidate.next_attempt_at IS NOT NULL
          AND candidate.next_attempt_at <= ?
          AND candidate.attempts < ?
          AND NOT EXISTS (
            SELECT 1
            FROM pending_chat_operations AS predecessor
            WHERE predecessor.owner_user_id = candidate.owner_user_id
              AND predecessor.chat_id = candidate.chat_id
              AND predecessor.type IN ('text', 'image', 'audio', 'location')
              AND predecessor.next_attempt_at IS NOT NULL
              AND (
                predecessor.created_at < candidate.created_at
                OR (
                  predecessor.created_at = candidate.created_at
                  AND predecessor.id < candidate.id
                )
              )
          )
        ORDER BY candidate.next_attempt_at ASC, candidate.created_at ASC,
          candidate.id ASC
        LIMIT ?
      ''',
          variables: [
            Variable.withString(owner),
            Variable.withDateTime(dueAt.toUtc()),
            Variable.withInt(PendingMessageRetryPolicy.maxAutomaticAttempts),
            Variable.withInt(limit),
          ],
          readsFrom: {_database.pendingChatOperations},
        )
        .get();
    return rows.map(_mapPendingMessageOperationRow).toList(growable: false);
  }

  /// Returns the earliest retry time among the heads of all conversations.
  Future<DateTime?> readNextPendingAttemptAt({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row = await _database
        .customSelect(
          '''
        SELECT MIN(candidate.next_attempt_at) AS next_attempt_at
        FROM pending_chat_operations AS candidate
        WHERE candidate.owner_user_id = ?
          AND candidate.type IN ('text', 'image', 'audio', 'location')
          AND candidate.next_attempt_at IS NOT NULL
          AND candidate.attempts < ?
          AND NOT EXISTS (
            SELECT 1
            FROM pending_chat_operations AS predecessor
            WHERE predecessor.owner_user_id = candidate.owner_user_id
              AND predecessor.chat_id = candidate.chat_id
              AND predecessor.type IN ('text', 'image', 'audio', 'location')
              AND predecessor.next_attempt_at IS NOT NULL
              AND (
                predecessor.created_at < candidate.created_at
                OR (
                  predecessor.created_at = candidate.created_at
                  AND predecessor.id < candidate.id
                )
              )
          )
      ''',
          variables: [
            Variable.withString(owner),
            Variable.withInt(PendingMessageRetryPolicy.maxAutomaticAttempts),
          ],
          readsFrom: {_database.pendingChatOperations},
        )
        .getSingle();
    return row.readNullable<DateTime>('next_attempt_at')?.toUtc();
  }

  Future<PendingMessageOperation?> readPendingOperation(
    String id, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row =
        await (_database.select(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.id.equals(id) &
                  table.type.isIn(MessageType.values.map((type) => type.name)),
            ))
            .getSingleOrNull();
    return row == null ? null : _mapPendingMessageOperation(row);
  }

  Future<bool> markPendingAttemptStarted(
    String id, {
    required DateTime attemptedAt,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final affected =
        await (_database.update(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.id.equals(id) &
                  table.type.isIn(MessageType.values.map((type) => type.name)),
            ))
            .write(
              PendingChatOperationsCompanion(
                lastAttemptAt: Value(attemptedAt.toUtc()),
              ),
            );
    return affected > 0;
  }

  /// Records one failed automatic delivery. A null [nextAttemptAt] makes the
  /// operation manual-retry-only while preserving its payload and media.
  Future<bool> markPendingFailure(
    String id,
    Object error, {
    required int attempts,
    required DateTime? nextAttemptAt,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final affected =
        await (_database.update(_database.pendingChatOperations)..where(
              (table) => table.ownerUserId.equals(owner) & table.id.equals(id),
            ))
            .write(
              PendingChatOperationsCompanion(
                attempts: Value(attempts),
                lastError: Value(error.toString()),
                nextAttemptAt: Value(nextAttemptAt?.toUtc()),
              ),
            );
    return affected > 0;
  }

  Future<PendingMessageOperation?> requeuePendingOperation(
    String id, {
    required DateTime nextAttemptAt,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row =
        await (_database.select(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.id.equals(id) &
                  table.type.isIn(MessageType.values.map((type) => type.name)),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    await (_database.update(_database.pendingChatOperations)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.equals(id),
        ))
        .write(
          PendingChatOperationsCompanion(
            attempts: const Value(0),
            lastError: const Value(null),
            nextAttemptAt: Value(nextAttemptAt.toUtc()),
          ),
        );
    return _mapPendingMessageOperation(
      row.copyWith(
        attempts: 0,
        lastError: const Value(null),
        nextAttemptAt: Value(nextAttemptAt.toUtc()),
      ),
    );
  }

  Future<void> removePendingOperation(String id, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    await (_database.delete(_database.pendingChatOperations)..where(
          (table) => table.ownerUserId.equals(owner) & table.id.equals(id),
        ))
        .go();
  }

  PendingMessageOperation _mapPendingMessageOperation(
    PendingChatOperation row,
  ) {
    return PendingMessageOperation(
      id: row.id,
      chatId: row.chatId,
      type: row.type,
      payload: Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
      attempts: row.attempts,
      lastError: row.lastError,
      nextAttemptAt: row.nextAttemptAt?.toUtc(),
      lastAttemptAt: row.lastAttemptAt?.toUtc(),
      createdAt: row.createdAt.toUtc(),
    );
  }

  PendingMessageOperation _mapPendingMessageOperationRow(QueryRow row) {
    return PendingMessageOperation(
      id: row.read<String>('id'),
      chatId: row.read<String>('chat_id'),
      type: row.read<String>('type'),
      payload: Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      ),
      attempts: row.read<int>('attempts'),
      lastError: row.readNullable<String>('last_error'),
      nextAttemptAt: row.readNullable<DateTime>('next_attempt_at')?.toUtc(),
      lastAttemptAt: row.readNullable<DateTime>('last_attempt_at')?.toUtc(),
      createdAt: row.read<DateTime>('created_at').toUtc(),
    );
  }

  Future<void> putPendingChatDeletion({
    required String id,
    required String chatId,
    required DateTime clearedAt,
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    return _database
        .into(_database.pendingChatOperations)
        .insertOnConflictUpdate(
          PendingChatOperationsCompanion.insert(
            ownerUserId: owner,
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

  Future<List<PendingChatDeletion>> readPendingChatDeletions({
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final query = _database.select(_database.pendingChatOperations)
      ..where(
        (table) =>
            table.ownerUserId.equals(owner) &
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

  Future<ConversationCacheFiles> clearConversations(
    Set<String> chatIds, {
    String? ownerUserId,
  }) async {
    if (chatIds.isEmpty) return const ConversationCacheFiles();
    final owner = ownerUserId ?? _userIdProvider();
    final messageRows =
        await (_database.select(_database.cachedMessages)..where(
              (table) =>
                  table.ownerUserId.equals(owner) & table.chatId.isIn(chatIds),
            ))
            .get();
    final pendingRows =
        await (_database.select(_database.pendingChatOperations)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
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
      await (_database.delete(
            _database.cachedMessageReactionStates,
          )..where((t) => t.ownerUserId.equals(owner) & t.chatId.isIn(chatIds)))
          .go();
      await (_database.delete(
            _database.pendingMessageReactions,
          )..where((t) => t.ownerUserId.equals(owner) & t.chatId.isIn(chatIds)))
          .go();
      await (_database.delete(_database.cachedMessages)..where(
            (table) =>
                table.ownerUserId.equals(owner) & table.chatId.isIn(chatIds),
          ))
          .go();
      await (_database.delete(_database.pendingChatOperations)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
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

  Future<void> _upsertMessages(
    List<ChatMessage> messages,
    String ownerUserId,
  ) async {
    for (final message in messages) {
      if (_removedMessageKeys.contains(_messageKey(ownerUserId, message.id))) {
        continue;
      }
      await _database
          .into(_database.cachedMessages)
          .insertOnConflictUpdate(_messageCompanion(message, ownerUserId));
      await storeReactionState(
        message.chatId,
        message.id,
        message.reactionState,
        ownerUserId: ownerUserId,
      );
    }
  }

  CachedMessagesCompanion _messageCompanion(
    ChatMessage message,
    String ownerUserId, {
    bool isPending = false,
  }) {
    final reply = message.replyTo;
    return CachedMessagesCompanion.insert(
      ownerUserId: ownerUserId,
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
      isPending: isPending || message.isLocalOnly,
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
      isLocalOnly: row.isPending && row.status == MessageStatus.sent.name,
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
    this.nextAttemptAt,
    this.lastAttemptAt,
  });

  final String id;
  final String chatId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
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
