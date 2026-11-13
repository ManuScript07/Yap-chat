import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/history_viewport_transition.dart';

void main() {
  for (final older in [true, false]) {
    testWidgets('paint motion preserves layout and child state older=$older', (
      tester,
    ) async {
      final key = GlobalKey<HistoryViewportTransitionState>();
      final childKey = GlobalKey();
      var completed = 0;
      var layouts = 0;
      Widget view(int revision) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 300,
            child: HistoryViewportTransition(
              key: key,
              revision: revision,
              fromOlder: older,
              onCompleted: () => completed++,
              child: LayoutBuilder(
                key: childKey,
                builder: (_, _) {
                  layouts++;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(0));
      final element = childKey.currentContext;
      final origin = tester.getTopLeft(find.byKey(childKey));
      final size = tester.getSize(find.byKey(childKey));
      expect(key.currentState!.isAnimating, isFalse);
      await tester.pumpWidget(view(1));
      expect(key.currentState!.isAnimating, isTrue);
      final layoutsBeforeAnimation = layouts;
      final first = tester.getTopLeft(find.byKey(childKey));
      expect(first.dy - origin.dy, older ? -48 : 48);
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getTopLeft(find.byKey(childKey));
      expect((middle.dy - origin.dy).abs(), lessThan(48));
      expect((middle.dy - origin.dy).abs(), greaterThan(0));
      expect(tester.getSize(find.byKey(childKey)), size);
      expect(identical(element, childKey.currentContext), isTrue);
      await tester.pumpAndSettle();
      expect(layouts, layoutsBeforeAnimation);
      expect(tester.getTopLeft(find.byKey(childKey)), origin);
      expect(completed, 1);
      // Unrelated rebuild/pagination never starts another animation.
      await tester.pumpWidget(view(1));
      expect(key.currentState!.isAnimating, isFalse);
      expect(completed, 1);
      await tester.pumpWidget(view(2));
      key.currentState!.finish();
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(childKey)), origin);
      expect(key.currentState!.isAnimating, isFalse);
      expect(completed, 2);
      await tester.pumpWidget(view(3));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion disables and interrupts window motion', (
    tester,
  ) async {
    final key = GlobalKey<HistoryViewportTransitionState>();
    Widget view(int revision, bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: HistoryViewportTransition(
          key: key,
          revision: revision,
          fromOlder: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpWidget(view(0, true));
    await tester.pumpWidget(view(1, true));
    expect(key.currentState!.isAnimating, isFalse);
    await tester.pumpWidget(view(2, false));
    expect(key.currentState!.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(view(2, true));
    expect(key.currentState!.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });
}
