import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/focused_history_slice.dart';

void main() {
  test('older growth trims the newest side and retains an older cursor', () {
    final initial = List.generate(240, _message);
    final page = List.generate(60, (index) => _message(index + 240));
    final result = boundFocusedHistory([
      ...initial,
      ...page,
    ], FocusedHistoryGrowth.older);
    expect(result.trimmed, isTrue);
    expect(result.messages, hasLength(240));
    expect(result.messages.first.id, '60');
    expect(result.messages.last.id, '299');
    expect(result.messages.any((message) => message.id == '230'), isTrue);
  });

  test('newer growth trims the oldest side and retains a newer cursor', () {
    final initial = List.generate(240, (index) => _message(index + 60));
    final page = List.generate(60, _message);
    final result = boundFocusedHistory([
      ...page,
      ...initial,
    ], FocusedHistoryGrowth.newer);
    expect(result.trimmed, isTrue);
    expect(result.messages, hasLength(240));
    expect(result.messages.first.id, '0');
    expect(result.messages.last.id, '239');
    expect(result.messages.any((message) => message.id == '70'), isTrue);
  });

  test('short windows retain identity and do not change pagination flags', () {
    final messages = List.generate(60, _message);
    final result = boundFocusedHistory(messages, FocusedHistoryGrowth.older);
    expect(result.trimmed, isFalse);
    expect(identical(result.messages, messages), isTrue);
  });

  test('trimmed pages can be loaded again from the remaining edge cursor', () {
    final initial = List.generate(240, (index) => _message(index + 60));
    final newer = boundFocusedHistory(
      [...List.generate(60, _message), ...initial],
      FocusedHistoryGrowth.newer,
    ).messages;
    expect(newer.last.id, '239');

    final restored = boundFocusedHistory(
      [...newer, ...List.generate(60, (index) => _message(index + 240))],
      FocusedHistoryGrowth.older,
    ).messages;
    expect(restored.first.id, '60');
    expect(restored.last.id, '299');
    expect(restored.map((message) => message.id).toSet(), hasLength(240));
  });
}

ChatMessage _message(int index) => ChatMessage(
  id: '$index',
  chatId: 'chat',
  senderId: 'peer',
  text: '$index',
  timestamp: DateTime.utc(2026, 9, 26).subtract(Duration(minutes: index)),
  isMine: false,
);
