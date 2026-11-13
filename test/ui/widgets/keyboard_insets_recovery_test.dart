import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final hidePhase in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    testWidgets('background IME closure preserves search focus at $hidePhase', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(() {
        _resume(tester);
      });
      final focus = FocusNode();
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSearchBar(
              hintText: 'Search',
              focusNode: focus,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'keep search');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      if (hidePhase != AppLifecycleState.inactive) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      if (hidePhase == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      tester.testTextInput.hide();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(controller.text, 'keep search');
      _resume(tester);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      // Model Android restoring the existing editor, not a new focus request.
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .requestKeyboard();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      // An explicit hide in the foreground still clears search focus.
      tester.testTextInput.hide();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(controller.text, 'keep search');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      focus.dispose();
      controller.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('unfocused search cannot clear a different focused editor', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(tester.view.resetViewInsets);
    final search = FocusNode();
    final other = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GlassSearchBar(hintText: 'Search', focusNode: search),
              TextField(key: const ValueKey('other-editor'), focusNode: other),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('other-editor')), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(other.hasFocus, isTrue);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(other.hasFocus, isTrue);
    expect(search.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    search.dispose();
    other.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final landscape in [false, true]) {
    for (final keyboardRetained in [false, true]) {
      testWidgets(
        'search follows engine recovery landscape=$landscape retained=$keyboardRetained',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = landscape
              ? const Size(780, 390)
              : const Size(390, 780);
          addTearDown(tester.view.reset);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          addTearDown(() {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          });
          final controller = TextEditingController();
          final focus = FocusNode();
          await tester.pumpWidget(
            MaterialApp(
              home: KeyboardDismissPopScope(
                child: Scaffold(
                  resizeToAvoidBottomInset: false,
                  body: Builder(
                    builder: (context) {
                      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: keyboard > 0 ? keyboard + 16 : 102,
                            child: GlassSearchBar(
                              hintText: 'Search',
                              controller: controller,
                              focusNode: focus,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          double bottomOffset() =>
              tester.view.physicalSize.height -
              tester.getBottomRight(find.byType(GlassSearchBar)).dy;
          bool canPop() => tester
              .widget<PopScope>(
                find.byWidgetPredicate((widget) => widget is PopScope),
              )
              .canPop;
          expect(bottomOffset(), 102);
          await tester.enterText(find.byType(TextField), 'saved search');
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pumpAndSettle();
          expect(bottomOffset(), 256);
          expect(canPop(), isFalse);

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          if (!keyboardRetained) tester.testTextInput.hide();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          // Android has hidden the IME, but the engine's old inset still lifts
          // every page. Native recovery supplies a normal global metrics update.
          expect(bottomOffset(), 256);
          if (!keyboardRetained) {
            // A repeated old positive snapshot (for example from system-bar
            // metrics) is not evidence that the keyboard has been restored.
            tester.binding.handleMetricsChanged();
            tester.view.viewInsets = const FakeViewPadding();
          }
          await tester.pumpAndSettle();
          expect(bottomOffset(), keyboardRetained ? 256 : 102);
          expect(canPop(), !keyboardRetained);
          expect(controller.text, 'saved search');
          expect(tester.testTextInput.isVisible, keyboardRetained);
          expect(focus.hasFocus, isTrue);
          if (!keyboardRetained) {
            // A late hidden-IME metric on the FIRST return must not kill the
            // editor before Android gets a chance to restore its keyboard.
            tester
                .state<EditableTextState>(find.byType(EditableText))
                .requestKeyboard();
            tester.view.viewInsets = const FakeViewPadding(bottom: 240);
            await tester.pumpAndSettle();
            expect(bottomOffset(), 256);
            expect(tester.testTextInput.isVisible, isTrue);
          } else {
            // No fresh metric is required when Android kept the IME visible;
            // the transient guard still expires and cannot mask future hides.
            await tester.pump(const Duration(milliseconds: 1100));
          }
          tester.testTextInput.hide();
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isFalse);
          expect(canPop(), isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          controller.dispose();
          focus.dispose();
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
