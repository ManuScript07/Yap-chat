import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets(
    'inactive indexed tabs stop dot animation and resume when selected',
    (tester) async {
      final index = ValueNotifier(0);
      addTearDown(index.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (_, value, _) => IndexedStack(
              index: value,
              children: const [
                Center(
                  child: AnimatedConnectingText(
                    label: 'connecting…',
                    style: TextStyle(fontSize: 30),
                  ),
                ),
                SizedBox.expand(),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      index.value = 1;
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      index.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  testWidgets('dots fade one-two-three without changing word or label bounds', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Builder(
            builder: (context) {
              builds++;
              return const AnimatedConnectingText(
                label: 'соединение…',
                style: TextStyle(fontSize: 36, color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
    final label = find.byType(AnimatedConnectingText);
    final word = find.text('соединение');
    final labelRect = tester.getRect(label);
    final wordRect = tester.getRect(word);
    final wordElement = tester.element(word);
    List<double> opacity() => tester
        .widgetList<FadeTransition>(
          find.descendant(of: label, matching: find.byType(FadeTransition)),
        )
        .map((w) => w.opacity.value)
        .toList();
    expect(find.text('.'), findsNWidgets(3));
    expect(opacity(), [0, 0, 0]);
    await tester.pump(const Duration(milliseconds: 108));
    expect(opacity()[0], inExclusiveRange(0, 1));
    expect(opacity().skip(1), [0, 0]);
    await tester.pump(const Duration(milliseconds: 324));
    expect(opacity()[0], 1);
    expect(opacity()[1], inExclusiveRange(0, 1));
    expect(opacity()[2], 0);
    await tester.pump(const Duration(milliseconds: 648));
    expect(opacity(), [1, 1, 1]);
    await tester.pump(const Duration(milliseconds: 630));
    expect(opacity()[0], inExclusiveRange(0, 1));
    expect(opacity()[1], inExclusiveRange(0, 1));
    expect(opacity()[2], inExclusiveRange(0, 1));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getRect(label), labelRect);
      expect(tester.getRect(word), wordRect);
      expect(tester.element(word), same(wordElement));
      expect(builds, 1);
      expect(tester.takeException(), isNull);
    }
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('соединение…'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion is static and resumes only while enabled', (
    tester,
  ) async {
    final reduced = ValueNotifier(true);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: reduced,
          builder: (context, value, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: value),
            child: child!,
          ),
          child: const Center(
            child: AnimatedConnectingText(
              label: 'connecting…',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final fade in tester.widgetList<FadeTransition>(
      find.byType(FadeTransition),
    )) {
      expect(fade.opacity.value, 1);
    }
    expect(tester.binding.hasScheduledFrame, false);
    reduced.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, true);
    reduced.value = true;
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden routes mute the ticker without a timer', (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, value, child) =>
              TickerMode(enabled: value, child: child!),
          child: const Center(
            child: AnimatedConnectingText(
              label: 'connecting…',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    active.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    active.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, true);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
