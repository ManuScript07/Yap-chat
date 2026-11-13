import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final target in NavigationScrollTarget.values) {
    for (final count in [60, 1000]) {
      testWidgets(
        '$target returns $count loaded rows smoothly without replacing them',
        (tester) async {
          final owner = NavigationScrollToTopController();
          final scroll = ScrollController();
          final activity = <bool>[];
          await _mount(
            tester,
            owner,
            scroll,
            target: target,
            count: count,
            activity: activity.add,
          );
          scroll.jumpTo(scroll.position.maxScrollExtent - 200);
          await tester.pump();
          final before = scroll.offset;
          final view = tester.element(find.byType(ListView));
          final first = owner.scrollToTop(target);
          unawaited(owner.scrollToTop(target));
          await tester.pump();
          expect(scroll.offset, before);
          for (var i = 0; i < 42; i++) {
            final previous = scroll.offset;
            await tester.pump(const Duration(milliseconds: 16));
            expect(scroll.offset, lessThanOrEqualTo(previous));
            expect(scroll.offset, greaterThanOrEqualTo(0));
          }
          await first;
          expect(scroll.offset, 0);
          expect(activity, [true, false]);
          expect(tester.element(find.byType(ListView)), same(view));
          unawaited(owner.scrollToTop(target));
          await tester.pump();
          expect(activity, [true, false]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          scroll.dispose();
          owner.dispose();
        },
      );
    }
  }

  testWidgets('new pages and rotation do not restart the animation', (
    tester,
  ) async {
    final owner = NavigationScrollToTopController();
    final scroll = ScrollController();
    await _mount(tester, owner, scroll);
    scroll.jumpTo(1800);
    final done = owner.scrollToTop(NavigationScrollTarget.chats);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final offset = scroll.offset;
    await _mount(tester, owner, scroll, count: 150);
    expect(scroll.offset, closeTo(offset, .1));
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await done;
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    owner.dispose();
  });

  testWidgets(
    'a user drag interrupts the return and a subsequent command works',
    (tester) async {
      final owner = NavigationScrollToTopController();
      final scroll = ScrollController();
      final activity = <bool>[];
      await _mount(tester, owner, scroll, activity: activity.add);
      scroll.jumpTo(2200);
      final done = owner.scrollToTop(NavigationScrollTarget.chats);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await done;
      expect(scroll.offset, greaterThan(0));
      final retry = owner.scrollToTop(NavigationScrollTarget.chats);
      await tester.pumpAndSettle();
      await retry;
      expect(scroll.offset, 0);
      expect(activity, [true, false, true, false]);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      owner.dispose();
    },
  );

  testWidgets(
    'switching target controller stops the old list at its current offset',
    (tester) async {
      final owner = NavigationScrollToTopController();
      final friends = ScrollController(), requests = ScrollController();
      final activity = <bool>[];
      await _mount(tester, owner, friends, activity: activity.add);
      friends.jumpTo(2000);
      final done = owner.scrollToTop(NavigationScrollTarget.chats);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await _mount(tester, owner, requests, activity: activity.add);
      await tester.pumpAndSettle();
      await done;
      expect(activity, [true, false]);
      expect(requests.offset, 0);
      requests.jumpTo(1000);
      final again = owner.scrollToTop(NavigationScrollTarget.chats);
      await tester.pumpAndSettle();
      await again;
      expect(requests.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      friends.dispose();
      requests.dispose();
      owner.dispose();
    },
  );

  testWidgets('cancellation and disposal release an in-flight command', (
    tester,
  ) async {
    final owner = NavigationScrollToTopController();
    final scroll = ScrollController();
    final activity = <bool>[];
    await _mount(tester, owner, scroll, activity: activity.add);
    scroll.jumpTo(2000);
    final done = owner.scrollToTop(NavigationScrollTarget.chats);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    owner.cancel();
    final stopped = scroll.offset;
    await tester.pumpAndSettle();
    await done;
    expect(scroll.offset, stopped);
    expect(stopped, greaterThan(0));
    final pending = owner.scrollToTop(NavigationScrollTarget.chats);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pending;
    await owner.scrollToTop(NavigationScrollTarget.chats);
    expect(activity, [true, false, true, false]);
    expect(tester.takeException(), isNull);
    scroll.dispose();
    owner.dispose();
  });

  testWidgets(
    'reduced motion jumps directly, disabled and unmounted lists are no-ops',
    (tester) async {
      final owner = NavigationScrollToTopController();
      final scroll = ScrollController();
      await owner.scrollToTop(NavigationScrollTarget.chats);
      await _mount(tester, owner, scroll, enabled: false);
      scroll.jumpTo(1000);
      await owner.scrollToTop(NavigationScrollTarget.chats);
      expect(scroll.offset, 1000);
      await _mount(tester, owner, scroll, reducedMotion: true);
      await owner.scrollToTop(NavigationScrollTarget.chats);
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      scroll.dispose();
      owner.dispose();
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  NavigationScrollToTopController owner,
  ScrollController controller, {
  NavigationScrollTarget target = NavigationScrollTarget.chats,
  int count = 100,
  bool enabled = true,
  bool reducedMotion = false,
  ValueChanged<bool>? activity,
}) async {
  await tester.pumpWidget(
    RepositoryProvider.value(
      value: owner,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: NavigationScrollToTopTarget(
            target: target,
            controller: controller,
            enabled: enabled,
            onActivityChanged: activity,
            child: ListView.builder(
              key: ObjectKey(controller),
              controller: controller,
              itemCount: count,
              itemExtent: 80,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ),
        ),
      ),
    ),
  );
}
