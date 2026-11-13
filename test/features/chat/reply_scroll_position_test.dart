import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('swiping up in a reversed chat moves toward newer items', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final userDeltas = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 && notification.dragDetails != null) {
                userDeltas.add(notification.scrollDelta ?? 0);
              }
              return false;
            },
            child: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: positions,
              reverse: true,
              itemCount: 40,
              itemBuilder: (_, index) =>
                  SizedBox(height: 80, child: Text('message $index')),
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(index: 15);
    await tester.pumpAndSettle();
    final before = positions.itemPositions.value
        .map((position) => position.index)
        .reduce((a, b) => a < b ? a : b);
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    final after = positions.itemPositions.value
        .map((position) => position.index)
        .reduce((a, b) => a < b ? a : b);
    expect(userDeltas, isNotEmpty);
    expect(userDeltas.every((delta) => delta < 0), isTrue);
    expect(after, lessThan(before));
  });

  testWidgets(
    'return within the recent timeline animates before reaching message zero',
    (tester) async {
      final controller = ItemScrollController();
      final positions = ItemPositionsListener.create();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: positions,
              reverse: true,
              padding: const EdgeInsets.only(bottom: 82),
              itemCount: 100,
              itemBuilder: (_, index) =>
                  SizedBox(height: 70, child: Text('message $index')),
            ),
          ),
        ),
      );
      controller.jumpTo(index: 55, alignment: 0.5);
      await tester.pumpAndSettle();
      expect(_isVisible(positions, 55), isTrue);

      final animation = controller.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      expect(_isVisible(positions, 55), isTrue);
      await tester.pumpAndSettle();
      await animation;
      expect(_isVisible(positions, 0), isTrue);
    },
  );

  testWidgets('index navigation stays on variable-height message rows', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();

    Widget list(bool focused) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              bottom: 70,
              child: ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                itemCount: focused ? 80 : 60,
                itemBuilder: (_, index) => SizedBox(
                  height: index.isEven ? 58 : 220,
                  child: Text('message $index'),
                ),
              ),
            ),
            const Positioned(bottom: 0, child: SizedBox(height: 70)),
          ],
        ),
      ),
    );

    await tester.pumpWidget(list(false));
    await tester.pumpAndSettle();
    final scroll = controller.scrollTo(
      index: 45,
      alignment: 0.5,
      duration: const Duration(milliseconds: 350),
    );
    await tester.pumpAndSettle();
    await scroll;
    expect(_isVisible(positions, 45), isTrue);
    expect(find.text('message 45'), findsOneWidget);

    // A quoted message can be outside the contiguous recent-message page.
    await tester.pumpWidget(list(true));
    controller.jumpTo(index: 65, alignment: 0.5);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_isVisible(positions, 65), isTrue);
    expect(find.text('message 65'), findsOneWidget);

    await tester.pumpWidget(list(false));
    controller.jumpTo(index: 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_isVisible(positions, 0), isTrue);
  });

  testWidgets('leaving distant history mounts the recent timeline at bottom', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();

    Widget timeline({required bool focused}) => MaterialApp(
      home: Scaffold(
        body: ScrollablePositionedList.builder(
          key: ValueKey(focused ? 'focus_messages' : 'recent_messages'),
          itemScrollController: controller,
          itemPositionsListener: positions,
          reverse: true,
          padding: const EdgeInsets.only(bottom: 82),
          itemCount: focused ? 120 : 60,
          itemBuilder: (_, index) => SizedBox(
            height: index.isEven ? 58 : 180,
            child: Text(focused ? 'old $index' : 'recent $index'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(timeline(focused: true));
    controller.jumpTo(index: 85, alignment: 0.5);
    await tester.pumpAndSettle();
    expect(_isVisible(positions, 85), isTrue);

    await tester.pumpWidget(timeline(focused: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_isVisible(positions, 0), isTrue);
    expect(find.text('recent 0'), findsOneWidget);
  });

  testWidgets('replacing a focused window preserves its visible anchor', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();

    Widget window(List<int> messageIds) => MaterialApp(
      home: Scaffold(
        body: ScrollablePositionedList.builder(
          key: const ValueKey('focus_messages'),
          itemScrollController: controller,
          itemPositionsListener: positions,
          reverse: true,
          itemCount: messageIds.length,
          itemBuilder: (_, index) {
            final id = messageIds[index];
            return SizedBox(
              height: id.isEven ? 62 : 180,
              child: Text('message $id'),
            );
          },
        ),
      ),
    );

    await tester.pumpWidget(window(List.generate(120, (index) => index)));
    controller.jumpTo(index: 60, alignment: 0.34);
    await tester.pumpAndSettle();
    final before = positions.itemPositions.value.singleWhere(
      (position) => position.index == 60,
    );
    expect(_isVisible(positions, 60), isTrue);

    // A server recheck can prepend rows before the visible message.
    await tester.pumpWidget(window(List.generate(130, (index) => index - 10)));
    await tester.pump();
    controller.jumpTo(index: 70, alignment: before.itemLeadingEdge);
    await tester.pumpAndSettle();

    final after = positions.itemPositions.value.singleWhere(
      (position) => position.index == 70,
    );
    expect(find.text('message 60'), findsOneWidget);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.03));
    expect(tester.takeException(), isNull);

    // The first visible row may be only partly on-screen in a reversed list.
    controller.jumpTo(index: 70, alignment: -0.1);
    await tester.pumpAndSettle();
    final partiallyVisible = positions.itemPositions.value.singleWhere(
      (position) => position.index == 70,
    );
    controller.jumpTo(index: 70, alignment: partiallyVisible.itemLeadingEdge);
    await tester.pumpAndSettle();
    final preserved = positions.itemPositions.value.singleWhere(
      (position) => position.index == 70,
    );
    expect(
      preserved.itemLeadingEdge,
      closeTo(partiallyVisible.itemLeadingEdge, 0.03),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newer page can preserve the anchor in the first frame', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List.generate(80, (index) => index + 100);
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                itemCount: ids.length,
                itemBuilder: (_, index) => SizedBox(
                  height: ids[index].isEven ? 62 : 180,
                  child: Text('message ${ids[index]}'),
                ),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(index: 2, alignment: 0.25);
    await tester.pumpAndSettle();
    final before = positions.itemPositions.value.singleWhere(
      (position) => position.index == 2,
    );

    update(() => ids = [...List.generate(60, (index) => index + 40), ...ids]);
    controller.jumpTo(index: 62, alignment: before.itemLeadingEdge);
    await tester.pump();

    final after = positions.itemPositions.value.singleWhere(
      (position) => position.index == 62,
    );
    expect(find.text('message 102'), findsOneWidget);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.03));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first page can remount at an anchor beyond old itemCount', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List.generate(60, (index) => index + 100);
    var revision = 0;
    var initialIndex = 0;
    var initialAlignment = 0.0;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ScrollablePositionedList.builder(
                key: ValueKey('focus_$revision'),
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                initialScrollIndex: initialIndex,
                initialAlignment: initialAlignment,
                itemCount: ids.length,
                itemBuilder: (_, index) => SizedBox(
                  height: ids[index].isEven ? 62 : 180,
                  child: Text('message ${ids[index]}'),
                ),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(index: 3, alignment: 0.3);
    await tester.pumpAndSettle();
    final before = positions.itemPositions.value.singleWhere(
      (position) => position.index == 3,
    );

    update(() {
      ids = [...List.generate(60, (index) => index + 40), ...ids];
      revision++;
      initialIndex = 63;
      initialAlignment = before.itemLeadingEdge;
    });
    await tester.pump();

    final after = positions.itemPositions.value.singleWhere(
      (position) => position.index == 63,
    );
    expect(find.text('message 103'), findsOneWidget);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.03));
    expect(tester.takeException(), isNull);
  });

  testWidgets('trimming the opposite edge preserves the visible message', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List.generate(240, (index) => index);
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: positions,
                reverse: true,
                itemCount: ids.length,
                itemBuilder: (_, index) => SizedBox(
                  height: ids[index].isEven ? 62 : 180,
                  child: Text('message ${ids[index]}'),
                ),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(index: 225, alignment: 0.22);
    await tester.pumpAndSettle();
    final before = positions.itemPositions.value.singleWhere(
      (position) => position.index == 225,
    );

    update(() => ids = List.generate(240, (index) => index + 60));
    controller.jumpTo(index: 165, alignment: before.itemLeadingEdge);
    await tester.pump();

    final after = positions.itemPositions.value.singleWhere(
      (position) => position.index == 165,
    );
    expect(find.text('message 225'), findsOneWidget);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.03));
    expect(tester.takeException(), isNull);
  });
}

bool _isVisible(ItemPositionsListener listener, int index) {
  return listener.itemPositions.value.any(
    (item) =>
        item.index == index &&
        item.itemLeadingEdge < 1 &&
        item.itemTrailingEdge > 0,
  );
}
