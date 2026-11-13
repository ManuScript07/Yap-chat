import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets('chat edges track live keyboard and theme geometry', (
    tester,
  ) async {
    final style = ValueNotifier<ChatMediaShadowStyle>((
      topHeight: 84,
      bottomHeight: 110,
      bottomOffset: 0,
      backgroundColor: Colors.black,
    ));
    addTearDown(style.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMediaTransitionScope(
          child: Stack(
            children: [
              ValueListenableBuilder<ChatMediaShadowStyle>(
                valueListenable: style,
                builder: (_, value, _) => ChatMediaTransitionShadows(
                  topHeight: value.topHeight,
                  bottomHeight: value.bottomHeight,
                  bottomOffset: value.bottomOffset,
                  backgroundColor: value.backgroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    void expectEdges() {
      final edges = tester
          .widgetList<GradientOverlay>(find.byType(GradientOverlay))
          .toList();
      expect(edges, hasLength(2));
      expect(edges[0].height, style.value.topHeight);
      expect(edges[0].isTop, isTrue);
      expect(edges[1].height, style.value.bottomHeight);
      expect(edges[1].bottomOffset, style.value.bottomOffset);
      expect(edges[1].isTop, isFalse);
      expect(
        edges.map((edge) => edge.backgroundColor),
        everyElement(style.value.backgroundColor),
      );
    }

    expectEdges();
    style.value = (
      topHeight: 124,
      bottomHeight: 180,
      bottomOffset: 220,
      backgroundColor: const Color(0xff101820),
    );
    await tester.pump();
    expectEdges();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expectEdges();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shared shadows remain non-interactive and work without a scope',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(),
                ),
              ),
              const ChatMediaTransitionShadows(
                topHeight: 84,
                bottomHeight: 110,
                backgroundColor: Colors.black,
              ),
            ],
          ),
        ),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.tapAt(const Offset(10, 580));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
