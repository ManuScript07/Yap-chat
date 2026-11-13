import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/models/chat_message.dart';
import 'package:yap_chat/features/chat/view/focused_history_reconciliation.dart';

void main() {
  test('a shifted server page does not replace an unchanged open window', () {
    final loaded = List.generate(120, _message);
    final refreshed = List.generate(60, (index) => _message(index + 15));

    expect(reconcileFocusedHistory(loaded, refreshed), isNull);
  });

  test('an invisible message in the verified interval is removed', () {
    final loaded = List.generate(120, _message);
    final refreshed = [
      for (var index = 15; index <= 75; index++)
        if (index != 34) _message(index),
    ];

    final result = reconcileFocusedHistory(loaded, refreshed);
    expect(result, isNotNull);
    expect(result, hasLength(119));
    expect(result!.any((message) => message.id == _message(34).id), isFalse);
    expect(result.first.id, loaded.first.id);
    expect(result.last.id, loaded.last.id);
  });

  test('changed metadata is updated without dropping the other pages', () {
    final loaded = List.generate(120, _message);
    final changed = _message(34).copyWith(readAt: DateTime.utc(2026, 9, 26));
    final refreshed = [
      for (var index = 15; index < 75; index++)
        index == 34 ? changed : _message(index),
    ];

    final result = reconcileFocusedHistory(loaded, refreshed);
    expect(result, hasLength(120));
    expect(result![34], changed);
    expect(result[100], loaded[100]);
  });

  test('equal timestamps use message IDs to bound the verified range', () {
    final timestamp = DateTime.utc(2026, 9, 26);
    final loaded = [
      for (final id in ['d', 'c', 'b', 'a'])
        ChatMessage(
          id: id,
          chatId: 'chat',
          senderId: 'sender',
          text: id,
          timestamp: timestamp,
          isMine: false,
        ),
    ];
    final refreshed = [loaded[0], loaded[2], loaded[3]];

    final result = reconcileFocusedHistory(loaded, refreshed);
    expect(result?.map((message) => message.id), ['d', 'b', 'a']);
  });

  test('read status updates reuse an already hydrated image', () {
    final raw = _message(
      4,
    ).copyWith(type: MessageType.image, mediaStoragePaths: ['image/4']);
    final hydrated = raw.copyWith(mediaUrls: ['cached/image/4']);
    final updated = raw.copyWith(readAt: DateTime.utc(2026, 9, 26));

    expect(sameFocusedMediaSource(raw, updated), isTrue);
    final displayed = withFocusedCachedMedia(updated, hydrated);
    expect(displayed.readAt, updated.readAt);
    expect(displayed.mediaUrls, hydrated.mediaUrls);
  });

  test('a replaced media source never reuses the previous local file', () {
    final raw = _message(
      4,
    ).copyWith(type: MessageType.audio, audioStoragePath: 'audio/old');
    final hydrated = raw.copyWith(audioUrl: 'cached/audio/old');
    final replaced = raw.copyWith(audioStoragePath: 'audio/new');

    expect(sameFocusedMediaSource(raw, replaced), isFalse);
    expect(withFocusedCachedMedia(replaced, hydrated), replaced);
  });
}

ChatMessage _message(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(3, '0')}',
  chatId: 'chat',
  senderId: 'sender',
  text: 'message $index',
  timestamp: DateTime.utc(2026, 9, 26).subtract(Duration(minutes: index)),
  isMine: false,
);
