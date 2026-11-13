import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('a bottom jump does not restart the new message entrance', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final older = _message('older');
    final incoming = _message('incoming');

    Widget screen({required bool showIncoming}) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              bottom: 70,
              child: ScrollablePositionedList.builder(
                itemScrollController: controller,
                reverse: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: showIncoming ? 2 : 1,
                itemBuilder: (context, index) => MessageBubble(
                  key: ValueKey(
                    index == 0 && showIncoming ? 'incoming' : 'older',
                  ),
                  message: index == 0 && showIncoming ? incoming : older,
                  initialAnimationProgress: index == 0 && showIncoming ? 0 : 1,
                  maxWidth: 240,
                  peerName: 'Peer',
                ),
              ),
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SizedBox(key: ValueKey('composer'), height: 70),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(screen(showIncoming: false));
    await tester.pumpWidget(screen(showIncoming: true));
    await tester.pump(const Duration(milliseconds: 80));
    final beforeJump = _opacity(tester);
    expect(beforeJump, greaterThan(0));
    expect(beforeJump, lessThan(1));

    controller.jumpTo(index: 0);
    await tester.pump();
    final afterJump = _opacity(tester);
    expect(afterJump, greaterThanOrEqualTo(beforeJump));
    expect(afterJump, lessThanOrEqualTo(1));

    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 1);
    expect(tester.takeException(), isNull);

    final viewport = tester.getRect(find.byType(ScrollablePositionedList));
    final composer = tester.getRect(find.byKey(const ValueKey('composer')));
    expect(viewport.bottom, composer.top);
  });
}

ChatMessage _message(String id) => ChatMessage(
  id: id,
  chatId: 'chat',
  senderId: 'peer',
  text: id,
  timestamp: DateTime(2026),
  isMine: false,
);

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('incoming')),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;
