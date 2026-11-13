import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets(
    'page changes beyond the viewport do not rebase scroll coordinates',
    (tester) async {
      final controller = ItemScrollController();
      var ids = List.generate(120, (i) => i);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              final snapshot = ids;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                reverse: true,
                itemCount: snapshot.length,
                maintainVisiblePosition: true,
                itemKeyBuilder: (i) => ValueKey(snapshot[i]),
                itemBuilder: (_, i) =>
                    _Row(key: ValueKey('row_${snapshot[i]}'), id: snapshot[i]),
              );
            },
          ),
        ),
      );
      controller.jumpTo(index: 35, alignment: .3007);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('row_35'));
      final state = tester.state(row);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ScrollablePositionedList)),
      );
      await gesture.moveBy(const Offset(0, -37.35));
      await tester.pump();
      final position = Scrollable.of(tester.element(row)).position;
      final pixels = position.pixels;
      final y = tester.getTopLeft(row).dy;
      for (final count in [180, 90, 240, 120]) {
        update(() => ids = List.generate(count, (i) => i));
        await tester.pump();
        expect(position.pixels, closeTo(pixels, .000001));
        expect(tester.getTopLeft(row).dy, closeTo(y, .000001));
        expect(tester.state(row), same(state));
        expect(position.activity, isA<DragScrollActivity>());
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final delta in [-17.35, 17.35]) {
    for (final axis in Axis.values) {
      for (final reverse in [false, true]) {
        testWidgets(
          'fractional coordinates survive page rebasing delta=$delta axis=$axis reverse=$reverse',
          (tester) async {
            final controller = ItemScrollController();
            var ids = List.generate(180, (i) => 1000 + i);
            late StateSetter update;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (_, setState) {
                      update = setState;
                      final snapshot = ids;
                      return ScrollablePositionedList.builder(
                        itemScrollController: controller,
                        reverse: reverse,
                        scrollDirection: axis,
                        itemKeyBuilder: (i) => ValueKey(snapshot[i]),
                        maintainVisiblePosition: true,
                        itemCount: snapshot.length,
                        itemBuilder: (_, i) => SizedBox(
                          width: 90.35,
                          child: _Row(
                            key: ValueKey('row_${snapshot[i]}'),
                            id: snapshot[i],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            controller.jumpTo(index: 35, alignment: .3007);
            await tester.pumpAndSettle();
            final row = find.byKey(const ValueKey('row_1035'));
            double coordinate() => axis == Axis.vertical
                ? tester.getTopLeft(row).dy
                : tester.getTopLeft(row).dx;
            Offset movement(double value) =>
                axis == Axis.vertical ? Offset(0, value) : Offset(value, 0);
            final gesture = await tester.startGesture(
              tester.getCenter(find.byType(ScrollablePositionedList)),
            );
            await gesture.moveBy(movement(-30));
            await tester.pump();
            final errors = <double>[];
            final movements = <double>[];
            for (var i = 0; i < 10; i++) {
              final prior = coordinate();
              await gesture.moveBy(movement(delta));
              await tester.pump();
              final y = coordinate();
              movements.add(y - prior);
              update(
                () => ids = i.isEven ? [ids.first - 1, ...ids] : ids.sublist(1),
              );
              await tester.pump();
              errors.add(coordinate() - y);
            }
            // ignore: avoid_print
            print(
              'FRACTIONAL_REBASE requestedDy=$delta movements=$movements errors=$errors',
            );
            expect(errors.every((error) => error.abs() < 0.000001), isTrue);
            for (final movement in movements) {
              expect(movement, closeTo(delta, 0.000001));
            }
            await gesture.up();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final delta in [-35.0, 35.0]) {
    testWidgets(
      'a page in the same frame retains unmeasured pointer movement $delta',
      (tester) async {
        final controller = ItemScrollController();
        var ids = List.generate(180, (i) => 1000 + i);
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  final snapshot = ids;
                  return ScrollablePositionedList.builder(
                    itemScrollController: controller,
                    itemKeyBuilder: (i) => ValueKey(snapshot[i]),
                    maintainVisiblePosition: true,
                    reverse: true,
                    itemCount: snapshot.length,
                    itemBuilder: (_, i) => _Row(
                      key: ValueKey('row_${snapshot[i]}'),
                      id: snapshot[i],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        controller.jumpTo(index: 35, alignment: .3);
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('row_1035'));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ScrollablePositionedList)),
        );
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        final y = tester.getTopLeft(row).dy;
        await gesture.moveBy(Offset(0, delta));
        // Do not publish another frame of positions before applying the new page.
        update(() => ids = [for (var i = 940; i < 1000; i++) i, ...ids]);
        await tester.pump();
        final dy = tester.getTopLeft(row).dy - y;
        // ignore: avoid_print
        print(
          'SAME_FRAME_PAGE_DRAG requestedDy=$delta actualDy=$dy activity=${Scrollable.of(tester.element(row)).position.activity.runtimeType}',
        );
        expect(dy, closeTo(delta, 1));
        expect(
          Scrollable.of(tester.element(row)).position.activity,
          isA<DragScrollActivity>(),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final action in ['jump', 'replace', 'navigate-again']) {
    testWidgets('cancel pending long transition safely: $action', (
      tester,
    ) async {
      final controller = ItemScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemCount: 100,
              reverse: true,
              initialScrollIndex: 70,
              itemKeyBuilder: (i) => ValueKey(i),
              itemBuilder: (_, i) =>
                  SizedBox(height: 90, child: Text('message $i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var completed = false;
      final navigation = controller.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 250),
      );
      unawaited(navigation.then((_) => completed = true));
      // Runs before the secondary list's post-mount callback. This is the
      // cancellation gap exposed by an outbox jump during IME animation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (action != 'replace') controller.jumpTo(index: 0);
        if (action == 'navigate-again') {
          unawaited(
            controller.scrollTo(
              index: 40,
              duration: const Duration(milliseconds: 250),
            ),
          );
        }
      });
      if (action == 'replace') {
        await tester.pumpWidget(const SizedBox());
      } else {
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
      if (action != 'replace') {
        final fades = tester.widgetList<FadeTransition>(
          find.byWidgetPredicate(
            (w) =>
                w is FadeTransition &&
                w.child is NotificationListener<ScrollNotification>,
          ),
        );
        expect(fades.any((w) => w.opacity.value > .99), isTrue);
      }
    });
  }

  testWidgets(
    'keyed page rebases a fling without stopping or restarting row state',
    (tester) async {
      final controller = ItemScrollController();
      final positions = ItemPositionsListener.create();
      var ids = List.generate(240, (i) => 1000 + i);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                final snapshot = ids;
                return ScrollablePositionedList.builder(
                  itemScrollController: controller,
                  itemPositionsListener: positions,
                  itemKeyBuilder: (i) => ValueKey(snapshot[i]),
                  maintainVisiblePosition: true,
                  reverse: true,
                  itemCount: snapshot.length,
                  itemBuilder: (_, i) => _Row(
                    key: ValueKey('row_${snapshot[i]}'),
                    id: snapshot[i],
                  ),
                );
              },
            ),
          ),
        ),
      );
      controller.jumpTo(index: 30, alignment: .3);
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ScrollablePositionedList),
        const Offset(0, -180),
        900,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final anchor = positions.itemPositions.value.firstWhere(
        (p) => p.itemLeadingEdge >= 0 && p.itemTrailingEdge <= 1,
      );
      final id = ids[anchor.index];
      final row = find.byKey(ValueKey('row_$id'));
      final state = tester.state(row);
      final position = Scrollable.of(tester.element(row)).position;
      final velocity = position.activity!.velocity;
      final y = tester.getTopLeft(row).dy;
      expect(position.activity, isA<BallisticScrollActivity>());
      update(
        () => ids = [for (var i = 940; i < 1000; i++) i, ...ids.take(180)],
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(identical(state, tester.state(row)), isTrue);
      expect(position.activity, isA<BallisticScrollActivity>());
      expect(position.activity!.velocity, closeTo(velocity, 1));
      expect(tester.getTopLeft(row).dy, closeTo(y, 1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(row).dy, lessThan(y - 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final initialCount in [60, 240]) {
    for (final direction in [-1, 1]) {
      testWidgets(
        'keyed history retains drag, row state and position: $initialCount/$direction',
        (tester) async {
          final controller = ItemScrollController();
          final positions = ItemPositionsListener.create();
          var ids = List.generate(initialCount, (i) => 1000 + i);
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    final snapshot = ids;
                    return ScrollablePositionedList.builder(
                      itemScrollController: controller,
                      itemPositionsListener: positions,
                      itemKeyBuilder: (i) => ValueKey(snapshot[i]),
                      maintainVisiblePosition: true,
                      reverse: true,
                      itemCount: snapshot.length,
                      itemBuilder: (_, i) => _Row(
                        key: ValueKey('row_${snapshot[i]}'),
                        id: snapshot[i],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          controller.jumpTo(
            index: direction < 0 ? 5 : initialCount - 12,
            alignment: .3,
          );
          await tester.pumpAndSettle();
          final list = find.byType(ScrollablePositionedList);
          final gesture = await tester.startGesture(tester.getCenter(list));
          await gesture.moveBy(Offset(0, 25.0 * direction));
          await tester.pump();
          final anchor = positions.itemPositions.value.firstWhere(
            (p) => p.itemLeadingEdge >= 0 && p.itemTrailingEdge <= 1,
          );
          final id = ids[anchor.index];
          final row = find.byKey(ValueKey('row_$id'));
          final beforeState = tester.state(row);
          final beforePosition = Scrollable.of(tester.element(row)).position;
          final beforeY = tester.getTopLeft(row).dy;
          expect(beforePosition.activity, isA<DragScrollActivity>());
          update(() {
            if (direction < 0) {
              ids = [
                for (var i = ids.first - 60; i < ids.first; i++) i,
                ...ids,
              ];
              if (ids.length > 240) ids = ids.take(240).toList();
            } else {
              ids = [
                ...ids,
                for (var i = ids.last + 1; i <= ids.last + 60; i++) i,
              ];
              if (ids.length > 240) ids = ids.skip(ids.length - 240).toList();
            }
          });
          await tester.pump();
          expect(tester.takeException(), isNull);
          final afterPosition = Scrollable.of(tester.element(row)).position;
          expect(identical(beforePosition, afterPosition), isTrue);
          expect(afterPosition.activity, isA<DragScrollActivity>());
          expect(identical(beforeState, tester.state(row)), isTrue);
          expect(tester.getTopLeft(row).dy, closeTo(beforeY, 1));
          await gesture.moveBy(Offset(0, 30.0 * direction));
          await tester.pump();
          expect(
            (tester.getTopLeft(row).dy - beforeY) * direction,
            greaterThan(20),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.id});
  final int id;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 70 + (widget.id % 4) * 15.0,
    child: Text('message ${widget.id} ❤️'),
  );
}
