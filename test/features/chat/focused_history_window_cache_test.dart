import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/focused_history_window_cache.dart';

void main() {
  test('retains SQLite origin through hits and reaction updates', () {
    final cache = FocusedHistoryWindowCache();
    cache.remember('local', [_message('local')], usesLocalHistory: true);
    cache.remember('remote', [_message('remote')]);
    expect(cache.findSnapshot('local')!.usesLocalHistory, isTrue);
    expect(cache.findSnapshot('remote')!.usesLocalHistory, isFalse);
    cache.updateReaction('local', const MessageReactionState(version: 1));
    expect(cache.findSnapshot('local')!.usesLocalHistory, isTrue);
    expect(cache.findSnapshot('remote')!.usesLocalHistory, isFalse);
  });
  test('reaction patches cached windows without extending their lifetime', () {
    var now = DateTime.utc(2026);
    final cache = FocusedHistoryWindowCache(now: () => now);
    cache.remember('a', [_message('a')]);
    const reaction = MessageReactionState(
      version: 2,
      reactions: [MessageReaction(userId: 'peer', code: ReactionCode.fire)],
    );
    cache.updateReaction('a', reaction);
    expect(cache.find('a')!.single.reactionState, reaction);
    cache.updateReaction('a', const MessageReactionState(version: 1));
    expect(cache.find('a')!.single.reactionState, reaction);
    now = now.add(const Duration(minutes: 2));
    expect(cache.find('a'), isNull);
  });
  test('reuses either message in a window, but keeps only two windows', () {
    var now = DateTime.utc(2026, 9, 25);
    final cache = FocusedHistoryWindowCache(now: () => now);
    cache.remember('a', [_message('a'), _message('b')]);
    expect(cache.find('b')?.map((m) => m.id), ['a', 'b']);
    cache.remember('c', [_message('c')]);
    cache.find('a'); // Mark the first window as recently used.
    cache.remember('d', [_message('d')]);
    expect(cache.find('c'), isNull);
    expect(cache.find('b'), isNotNull);
    cache.clear(); // Deletion or Realtime reconnection invalidates snapshots.
    expect(cache.find('a'), isNull);

    cache.remember('e', [_message('e')]);
    now = now.add(const Duration(minutes: 2));
    expect(cache.find('e'), isNull);
  });
}

ChatMessage _message(String id) => ChatMessage(
  id: id,
  chatId: 'chat',
  senderId: 'peer',
  text: id,
  timestamp: DateTime.utc(2026, 9, 25),
  isMine: false,
);
