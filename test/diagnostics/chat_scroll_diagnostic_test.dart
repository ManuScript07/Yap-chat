// Opt-in diagnosis of the exact positioned-list operations used by ChatPage.
// Run with --dart-define=CHAT_SCROLL_DIAGNOSTIC=true. No app/runtime changes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _enabled = bool.fromEnvironment('CHAT_SCROLL_DIAGNOSTIC');

void main() {
  testWidgets('diagnostic: page remount interrupts an active drag', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List.generate(60, (i) => 100 + i);
    var revision = 0;
    var initialIndex = 0;
    var alignment = 0.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return ScrollablePositionedList.builder(
                key: ValueKey(revision),
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                initialScrollIndex: initialIndex,
                initialAlignment: alignment,
                itemCount: ids.length,
                itemBuilder: (_, i) => SizedBox(
                  height: 70,
                  child: _PillRow(key: ValueKey(ids[i]), id: ids[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(index: 5, alignment: .3);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollablePositionedList)),
    );
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    final anchor = positions.itemPositions.value
        .where((p) => p.itemLeadingEdge >= 0 && p.itemTrailingEdge <= 1)
        .first;
    final id = ids[anchor.index];
    final finder = find.byKey(ValueKey(id));
    final rowBefore = tester.state(finder);
    final scrollBefore = Scrollable.of(tester.element(finder)).position;
    final draggingBefore = scrollBefore.activity is DragScrollActivity;
    update(() {
      ids = [...List.generate(60, (i) => 40 + i), ...ids];
      revision++;
      initialIndex = anchor.index + 60;
      alignment = anchor.itemLeadingEdge;
    });
    await tester.pump();
    final rowAfter = tester.state(finder);
    final draggingAfter =
        Scrollable.of(tester.element(finder)).position.activity
            is DragScrollActivity;
    // Current implementation diagnosis, not an acceptance test for the fix.
    // ignore: avoid_print
    print(
      'PAGE_REMOUNT drag_before=$draggingBefore drag_after=$draggingAfter row_state_retained=${identical(rowBefore, rowAfter)}',
    );
    expect(draggingBefore, isTrue);
    expect(draggingAfter, isFalse);
    expect(identical(rowBefore, rowAfter), isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);

  testWidgets('diagnostic: in-place page jump interrupts an active drag', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List.generate(180, (i) => 100 + i);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                itemCount: ids.length,
                itemBuilder: (_, i) => SizedBox(
                  height: 70,
                  child: _PillRow(key: ValueKey(ids[i]), id: ids[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(index: 5, alignment: .3);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrollablePositionedList)),
    );
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    final anchor = positions.itemPositions.value
        .where((p) => p.itemLeadingEdge >= 0 && p.itemTrailingEdge <= 1)
        .first;
    final id = ids[anchor.index];
    final finder = find.byKey(ValueKey(id));
    final rowBefore = tester.state(finder);
    final before =
        Scrollable.of(tester.element(finder)).position.activity
            is DragScrollActivity;
    update(() => ids = [...List.generate(60, (i) => 40 + i), ...ids]);
    controller.jumpTo(
      index: anchor.index + 60,
      alignment: anchor.itemLeadingEdge,
    );
    await tester.pump();
    final after =
        Scrollable.of(tester.element(finder)).position.activity
            is DragScrollActivity;
    // ignore: avoid_print
    print(
      'PAGE_JUMP drag_before=$before drag_after=$after row_state_retained=${identical(rowBefore, tester.state(finder))}',
    );
    expect(before, isTrue);
    expect(after, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);

  for (final delay in [0, 1, 16, 60, 130]) {
    testWidgets(
      'diagnostic: animated bottom and cache jump overlap delay=$delay',
      (tester) async {
        final controller = ItemScrollController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScrollablePositionedList.builder(
                itemScrollController: controller,
                reverse: true,
                itemCount: 60,
                initialScrollIndex: 35,
                itemBuilder: (_, i) =>
                    SizedBox(height: 100, child: Text('message $i')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        unawaited(
          controller.scrollTo(
            index: 0,
            alignment: .13,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
        if (delay == 0) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => controller.jumpTo(index: 0),
          );
        } else {
          await tester.pump();
          await tester.pump(Duration(milliseconds: delay));
          controller.jumpTo(index: 0);
        }
        await tester.pumpAndSettle();
        final fade = tester
            .widgetList<FadeTransition>(find.byType(FadeTransition))
            .map((f) => f.opacity.value)
            .toList();
        // ignore: avoid_print
        print('BOTTOM_RACE delay=$delay opacity=$fade');
        expect(fade, isNotEmpty);
        expect(fade.first, 1);
        expect(tester.takeException(), isNull);
      },
      skip: !_enabled,
    );
  }
}

class _PillRow extends StatefulWidget {
  const _PillRow({super.key, required this.id});
  final int id;
  @override
  State<_PillRow> createState() => _PillRowState();
}

class _PillRowState extends State<_PillRow> {
  @override
  Widget build(BuildContext context) => Text('message ${widget.id} ❤️');
}
