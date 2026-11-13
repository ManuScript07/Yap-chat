import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('a rebuilt message does not replay its entrance animation', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'new-message',
      chatId: 'chat',
      senderId: 'peer',
      text: 'hello',
      timestamp: DateTime(2026),
      isMine: false,
    );

    Widget screen(double progress) => MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          initialAnimationProgress: progress,
          maxWidth: 240,
          peerName: 'Peer',
        ),
      ),
    );

    await tester.pumpWidget(screen(0));
    expect(_opacity(tester), lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester), 1);

    // Status and history updates rebuild the same row, but must not flash it.
    await tester.pumpWidget(screen(0));
    expect(_opacity(tester), 1);

    // If a virtualized row is mounted again after its entrance window,
    // the parent supplies completed progress.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(screen(1));
    expect(_opacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}

double _opacity(WidgetTester tester) =>
    tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(FadeTransition),
          ).first,
        )
        .opacity
        .value;
