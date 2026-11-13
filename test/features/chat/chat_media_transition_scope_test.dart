import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';

void main() {
  testWidgets('flight only toggles the active source, not every cached photo', (
    tester,
  ) async {
    final key = GlobalKey();
    late ChatMediaLocalFlight flight;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMediaTransitionScope(
          child: Builder(
            builder: (context) {
              flight = ChatMediaTransitionScope.maybeOf(context)!.localFlight;
              return Stack(
                children: [
                  Positioned(
                    top: 100,
                    left: 100,
                    child: SizedBox(key: key, width: 80, height: 60),
                  ),
                  const Positioned.fill(child: ChatMediaTransitionLayer()),
                ],
              );
            },
          ),
        ),
      ),
    );
    final hidden = List.generate(100, (_) => ValueNotifier(false));
    final changes = List.filled(100, 0);
    for (var i = 0; i < hidden.length; i++) {
      hidden[i].addListener(() => changes[i]++);
      flight.register(
        tag: 'm$i',
        key: key,
        path: '/missing-$i.jpg',
        cacheWidth: 200,
        radius: BorderRadius.circular(20),
        gallery: false,
        hidden: hidden[i],
      );
    }
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 260),
    );
    flight.follow(animation, tag: 'm0', ratio: 1);
    unawaited(animation.forward());
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(changes.first, 1);
    expect(changes.skip(1), everyElement(0));
    unawaited(animation.reverse());
    await tester.pumpAndSettle();
    expect(changes.first, 2);
    expect(changes.skip(1), everyElement(0));
    expect(hidden.every((value) => !value.value), isTrue);
    animation.dispose();
    await tester.pumpWidget(const SizedBox());
    for (final value in hidden) {
      value.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  for (final safeTop in [0.0, 24.0, 40.5]) {
    testWidgets('live header geometry includes safe area $safeTop', (
      tester,
    ) async {
      late BuildContext source;
      final height = ValueNotifier(64 + safeTop);
      addTearDown(height.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatMediaTransitionScope(
            child: Builder(
              builder: (context) {
                source = context;
                return ValueListenableBuilder<double>(
                  valueListenable: height,
                  builder: (_, value, _) => Align(
                    alignment: Alignment.topCenter,
                    child: ChatMediaTransitionChrome(
                      child: SizedBox(width: 300, height: value),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final geometry = ChatMediaTransitionScope.maybeOf(source)!;
      expect(geometry.headerRect!.height, 64 + safeTop);
      height.value += 12;
      await tester.pump();
      expect(geometry.headerRect!.height, 76 + safeTop);
      await tester.pumpWidget(const SizedBox());
      expect(geometry.headerRect, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final openingTime in [30, 300]) {
    testWidgets(
      'navigation keeps header mounted without fading opening=$openingTime',
      (tester) async {
        late BuildContext source;
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ChatMediaTransitionScope(
              child: Builder(
                builder: (context) {
                  source = context;
                  return ChatMediaTransitionChrome(
                    child: Builder(
                      builder: (_) {
                        builds++;
                        return const SizedBox(
                          key: ValueKey('header'),
                          width: 180,
                          height: 64,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final header = find.byKey(
          const ValueKey('header'),
          skipOffstage: false,
        );
        final element = tester.element(header);
        final bounds = tester.getRect(header);
        unawaited(
          Navigator.of(source).push(
            PageRouteBuilder<void>(
              opaque: false,
              transitionDuration: const Duration(milliseconds: 260),
              reverseTransitionDuration: const Duration(milliseconds: 180),
              pageBuilder: (_, _, _) => const Center(child: Text('gallery')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(Duration(milliseconds: openingTime));
        expect(
          find.ancestor(of: header, matching: find.byType(AnimatedOpacity)),
          findsNothing,
        );
        expect(tester.element(header), same(element));
        Navigator.of(source).pop();
        await tester.pumpAndSettle();
        expect(tester.element(header), same(element));
        expect(tester.getRect(header), bounds);
        expect(builds, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('different chats do not share header geometry', (tester) async {
    late ChatMediaTransitionGeometry first;
    late ChatMediaTransitionGeometry second;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            ChatMediaTransitionScope(
              child: Builder(
                builder: (context) {
                  first = ChatMediaTransitionScope.maybeOf(context)!;
                  return const ChatMediaTransitionChrome(
                    child: SizedBox(width: 300, height: 64),
                  );
                },
              ),
            ),
            ChatMediaTransitionScope(
              child: Builder(
                builder: (context) {
                  second = ChatMediaTransitionScope.maybeOf(context)!;
                  return const ChatMediaTransitionChrome(
                    child: SizedBox(width: 300, height: 88),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    expect(first, isNot(same(second)));
    expect(first.headerRect!.height, 64);
    expect(second.headerRect!.height, 88);
    expect(second.headerRect!.top, first.headerRect!.bottom);
  });

  testWidgets('outgoing buttons retain geometry until their animation ends', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    late ChatMediaTransitionGeometry geometry;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMediaTransitionScope(
          child: Builder(
            builder: (context) {
              geometry = ChatMediaTransitionScope.maybeOf(context)!;
              return Align(
                alignment: Alignment.bottomRight,
                child: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    // Match the chat's unkeyed fade/scale transition: outgoing
                    // and new buttons may coexist during a rapid reversal.
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: show
                        ? const ChatMediaTransitionChrome(
                            key: ValueKey('button'),
                            region: ChatMediaChromeRegion.scrollButton,
                            paintOutset: 8,
                            child: SizedBox(width: 50, height: 50),
                          )
                        : const SizedBox(
                            key: ValueKey('hidden'),
                            width: 50,
                            height: 50,
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(geometry.scrollButtonRects.single.size, const Size(66, 66));
    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(geometry.scrollButtonRects, hasLength(1));
    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(geometry.scrollButtonRects, hasLength(2));
    await tester.pumpAndSettle();
    expect(geometry.scrollButtonRects, hasLength(1));
    visible.value = false;
    await tester.pumpAndSettle();
    expect(geometry.scrollButtonRects, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(geometry.composerRect, isNull);
    expect(geometry.headerRect, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header without scope works normally', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(ChatMediaTransitionScope.maybeOf(context), isNull);
            return const ChatMediaTransitionChrome(child: Text('header'));
          },
        ),
      ),
    );
    expect(find.text('header'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
