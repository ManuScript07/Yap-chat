import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/visible_chat_read_selection.dart';

void main() {
  test('only fully visible unread incoming messages are selected', () {
    final messages = [
      _message('incoming'),
      _message('below'),
      _message('mine', isMine: true),
      _message('read', readAt: DateTime.utc(2026, 9, 26)),
      _message('acknowledged'),
    ];
    final result = visibleUnreadMessageIds(
      const [
        ItemPosition(index: 0, itemLeadingEdge: 0.1, itemTrailingEdge: 0.3),
        ItemPosition(index: 1, itemLeadingEdge: 0.95, itemTrailingEdge: 1.15),
        ItemPosition(index: 2, itemLeadingEdge: 0.3, itemTrailingEdge: 0.5),
        ItemPosition(index: 3, itemLeadingEdge: 0.5, itemTrailingEdge: 0.7),
        ItemPosition(index: 4, itemLeadingEdge: 0.7, itemTrailingEdge: 0.9),
        ItemPosition(index: 5, itemLeadingEdge: 0.9, itemTrailingEdge: 1),
      ],
      (index) => index < messages.length ? messages[index] : null,
      {'acknowledged'},
    );
    expect(result, {'incoming'});
  });

  test('a large bubble becomes read once most of the viewport shows it', () {
    expect(
      visibleUnreadMessageIds(
        const [
          ItemPosition(index: 0, itemLeadingEdge: -0.2, itemTrailingEdge: 1.2),
        ],
        (_) => _message('large'),
        {},
      ),
      {'large'},
    );
  });
}

ChatMessage _message(String id, {bool isMine = false, DateTime? readAt}) =>
    ChatMessage(
      id: id,
      chatId: 'chat',
      senderId: isMine ? 'me' : 'peer',
      text: id,
      timestamp: DateTime.utc(2026, 9, 26),
      isMine: isMine,
      readAt: readAt,
    );
