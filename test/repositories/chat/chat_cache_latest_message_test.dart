import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';

void main() {
  test('reads only the newest message with the same stable ordering as history',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const ownerUserId = 'owner';
    final cache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => ownerUserId,
    );
    final timestamp = DateTime.utc(2026, 9, 6, 12);

    await cache.upsertMessages([
      _message(id: 'old', timestamp: timestamp.subtract(const Duration(days: 1))),
      _message(id: 'same-time-a', timestamp: timestamp),
      _message(id: 'same-time-b', timestamp: timestamp),
    ]);

    final latest = await cache.readLatestMessage(
      'chat-id',
      currentUserId: ownerUserId,
    );

    expect(latest?.id, 'same-time-b');
  });
}

ChatMessage _message({required String id, required DateTime timestamp}) {
  return ChatMessage(
    id: id,
    chatId: 'chat-id',
    senderId: 'peer',
    text: id,
    timestamp: timestamp,
    isMine: false,
  );
}
