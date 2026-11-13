import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/ui/widgets/gradient_overlay.dart';

void main() {
  testWidgets(
    'latest message rests above composer but history passes behind it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const composerHeight = 74.0;
      final scroll = ItemScrollController();
      final positions = ItemPositionsListener.create();
      Widget screen({required double keyboardOffset}) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ScrollablePositionedList.builder(
                itemScrollController: scroll,
                itemPositionsListener: positions,
                reverse: true,
                padding: EdgeInsets.only(
                  bottom: composerHeight + keyboardOffset + 12,
                ),
                itemCount: 30,
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey('message_$index'),
                  height: 60,
                  child: Text('message $index'),
                ),
              ),
              GradientOverlay(
                height: composerHeight + 20,
                isTop: false,
                backgroundColor: Colors.black,
                bottomOffset: keyboardOffset,
              ),
              Positioned(
                bottom: keyboardOffset,
                left: 0,
                right: 0,
                height: composerHeight,
                child: const SizedBox(key: ValueKey('composer')),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(screen(keyboardOffset: 0));
      await tester.pumpAndSettle();

      final composerTop = tester
          .getTopLeft(find.byKey(const ValueKey('composer')))
          .dy;
      final gradientTop = tester.getTopLeft(find.byType(GradientOverlay)).dy;
      expect(gradientTop, composerTop - 20);
      final latestBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('message_0')))
          .dy;
      expect(latestBottom, lessThanOrEqualTo(composerTop));
      final newestAtBottom = positions.itemPositions.value.firstWhere(
        (position) => position.index == 0,
      );
      expect(
        newestAtBottom.itemLeadingEdge,
        closeTo((composerHeight + 12) / 800, 0.01),
      );

      scroll.jumpTo(index: 8);
      await tester.pumpAndSettle();
      final scrolledBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('message_8')))
          .dy;
      expect(scrolledBottom, greaterThan(composerTop));

      final returnAnimation = scroll.scrollTo(
        index: 0,
        alignment: (composerHeight + 12) / 800,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      await tester.pumpAndSettle();
      await returnAnimation;
      final afterAnimation = tester
          .getBottomLeft(find.byKey(const ValueKey('message_0')))
          .dy;
      expect(afterAnimation, lessThanOrEqualTo(composerTop));
      scroll.jumpTo(index: 0);
      await tester.pumpAndSettle();
      final afterJump = tester
          .getBottomLeft(find.byKey(const ValueKey('message_0')))
          .dy;
      expect(afterAnimation, closeTo(afterJump, 1));

      scroll.jumpTo(index: 2);
      await tester.pumpAndSettle();
      final nearbyReturn = scroll.scrollTo(
        index: 0,
        alignment: (composerHeight + 12) / 800,
        duration: const Duration(milliseconds: 250),
      );
      await tester.pumpAndSettle();
      await nearbyReturn;
      final afterNearbyReturn = tester
          .getBottomLeft(find.byKey(const ValueKey('message_0')))
          .dy;
      expect(afterNearbyReturn, closeTo(afterJump, 1));

      await tester.pumpWidget(screen(keyboardOffset: 280));
      scroll.jumpTo(index: 0);
      await tester.pumpAndSettle();
      final composerWithKeyboard = tester
          .getTopLeft(find.byKey(const ValueKey('composer')))
          .dy;
      final latestWithKeyboard = tester
          .getBottomLeft(find.byKey(const ValueKey('message_0')))
          .dy;
      expect(latestWithKeyboard, lessThanOrEqualTo(composerWithKeyboard));

      scroll.jumpTo(index: 8);
      await tester.pumpAndSettle();
      final keyboardReturn = scroll.scrollTo(
        index: 0,
        alignment: (composerHeight + 280 + 12) / 800,
        duration: const Duration(milliseconds: 250),
      );
      await tester.pumpAndSettle();
      await keyboardReturn;
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('message_0'))).dy,
        closeTo(latestWithKeyboard, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
