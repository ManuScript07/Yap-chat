import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

/// Frozen pre-optimization algorithm. Only private calls are replaced by their
/// public equivalents, within the same transaction. Do not optimize this oracle.
Future<void> storeHistoryPageReference(
  AppDatabase db,
  ChatCacheDataSource cache,
  String chatId,
  List<ChatMessage> messages, {
  required String ownerUserId,
  required ChatMessage boundary,
  required bool older,
}) => db.transaction(() async {
  final cached = {
    for (final m in await cache.readHistoryMessages(
      chatId,
      messages.map((m) => m.id).toSet(),
      ownerUserId: ownerUserId,
    ))
      m.id: m,
  };
  final cursor = ChatHistoryCursor.of(boundary);
  final table = db.cachedMessages;
  if (older || messages.isNotEmpty) {
    final edge = messages.isEmpty
        ? cursor
        : ChatHistoryCursor.of(older ? messages.last : messages.first);
    final missing =
        table.ownerUserId.equals(ownerUserId) &
        table.chatId.equals(chatId) &
        table.isPending.not() &
        (older
            ? cursor.before(table.timestampMicros, table.id)
            : cursor.after(table.timestampMicros, table.id)) &
        (older && messages.length < 60
            ? const Constant(true)
            : (older
                  ? edge.before(table.timestampMicros, table.id).not()
                  : edge.after(table.timestampMicros, table.id).not())) &
        table.id.isNotIn(messages.map((m) => m.id));
    final missingIds = db.selectOnly(table)
      ..addColumns([table.id])
      ..where(missing);
    await (db.delete(db.pendingMessageReactions)..where(
          (t) =>
              t.ownerUserId.equals(ownerUserId) &
              t.chatId.equals(chatId) &
              t.messageId.isInQuery(missingIds),
        ))
        .go();
    await (db.delete(db.cachedMessageReactionStates)..where(
          (t) =>
              t.ownerUserId.equals(ownerUserId) &
              t.chatId.equals(chatId) &
              t.messageId.isInQuery(missingIds),
        ))
        .go();
    await (db.update(table)..where(
          (t) =>
              t.ownerUserId.equals(ownerUserId) &
              t.chatId.equals(chatId) &
              t.replyMessageId.isInQuery(missingIds),
        ))
        .write(
          const CachedMessagesCompanion(
            replyMessageId: Value(null),
            replySenderId: Value(null),
            replyType: Value(null),
            replyText: Value(null),
          ),
        );
    await (db.delete(table)..where((_) => missing)).go();
  }
  await cache.upsertMessages([
    for (final m in messages)
      if (cached[m.id] case final previous?)
        m.copyWith(
          mediaUrls:
              m.type == previous.type &&
                  _samePaths(m.mediaStoragePaths, previous.mediaStoragePaths) &&
                  m.mediaUrls.isEmpty
              ? previous.mediaUrls
              : m.mediaUrls,
          audioUrl:
              m.type == previous.type &&
                  m.audioStoragePath == previous.audioStoragePath
              ? m.audioUrl ?? previous.audioUrl
              : m.audioUrl,
        )
      else
        m,
  ], ownerUserId: ownerUserId);
  await ChatHistoryCoverage(db).record(
    ownerUserId,
    chatId,
    oldest: older && messages.isNotEmpty
        ? ChatHistoryCursor.of(messages.last)
        : cursor,
    newest: !older && messages.isNotEmpty
        ? ChatHistoryCursor.of(messages.first)
        : cursor,
    reachesStart: older && messages.length < 60,
  );
});

bool _samePaths(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
