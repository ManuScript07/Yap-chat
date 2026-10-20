import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/repositories/chat/chat_history_cursor.dart';

/// Persists only intervals proved by successful ordered server pages. Keeping
/// disjoint intervals prevents skipping a gap after more than one offline page.
class ChatHistoryCoverage {
  ChatHistoryCoverage(this.database);
  final AppDatabase database;

  Future<CachedChatHistoryRange?> containing(
    String owner,
    String chatId,
    ChatHistoryCursor cursor,
  ) async {
    final table = database.cachedChatHistoryRanges;
    return (database.select(table)
          ..where(
            (t) =>
                t.ownerUserId.equals(owner) &
                t.chatId.equals(chatId) &
                cursor.after(t.oldestMicros, t.oldestId).not() &
                cursor.before(t.newestMicros, t.newestId).not(),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> record(
    String owner,
    String chatId, {
    required ChatHistoryCursor oldest,
    required ChatHistoryCursor newest,
    required bool reachesStart,
  }) async {
    final table = database.cachedChatHistoryRanges;
    // Callers commit page rows and this interval in the same transaction.
    var lower = oldest;
    var upper = newest;
    var start = reachesStart;
    while (true) {
      final overlaps =
          await (database.select(table)..where(
                (t) =>
                    t.ownerUserId.equals(owner) &
                    t.chatId.equals(chatId) &
                    lower.before(t.newestMicros, t.newestId).not() &
                    upper.after(t.oldestMicros, t.oldestId).not(),
              ))
              .get();
      if (overlaps.isEmpty) break;
      if (overlaps.length == 1) {
        final existing = overlaps.single;
        if (ChatHistoryCursor(
                  existing.oldestMicros,
                  existing.oldestId,
                ).compareTo(lower) <=
                0 &&
            ChatHistoryCursor(
                  existing.newestMicros,
                  existing.newestId,
                ).compareTo(upper) >=
                0 &&
            (!start || existing.reachesStart)) {
          return;
        }
      }
      for (final range in overlaps) {
        final a = ChatHistoryCursor(range.oldestMicros, range.oldestId);
        final b = ChatHistoryCursor(range.newestMicros, range.newestId);
        if (a.compareTo(lower) < 0) lower = a;
        if (b.compareTo(upper) > 0) upper = b;
        start = start || range.reachesStart;
        await database.delete(table).delete(range);
      }
    }
    await database
        .into(table)
        .insert(
          CachedChatHistoryRangesCompanion.insert(
            ownerUserId: owner,
            chatId: chatId,
            oldestMicros: lower.micros,
            oldestId: lower.id,
            newestMicros: upper.micros,
            newestId: upper.id,
            reachesStart: start,
          ),
        );
  }

  Future<void> clear(String owner, Iterable<String> chatIds) async {
    await (database.delete(
      database.cachedChatHistoryRanges,
    )..where((t) => t.ownerUserId.equals(owner) & t.chatId.isIn(chatIds))).go();
  }
}
