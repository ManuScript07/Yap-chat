import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

const _portrait = Size(400, 800);
const _landscape = Size(800, 400);
const _draft = 'preserved search';
const _selection = TextSelection(baseOffset: 2, extentOffset: 9);
const _otherKey = ValueKey('other-editor');
const _resumeChannel = MethodChannel('com.yapchat.app/keyboard_resume');
const _android = TargetPlatformVariant({TargetPlatform.android});

void main() {
  for (final reverse in [false, true]) {
    for (final order in [
      'geometry first',
      'zero first',
      'atomic geometry and zero',
      'geometry in earlier frame',
      'final geometry with fresh inset',
    ]) {
      testWidgets('rotation preserves editor reverse=$reverse order=$order', (
        tester,
      ) async {
        final h = await _mount(tester, landscape: reverse);
        await _open(tester, h);
        final destination = reverse ? _portrait : _landscape;
        if (order == 'atomic geometry and zero') {
          _geometryAndInset(tester, destination, 0);
        } else if (order == 'zero first') {
          _inset(tester, 0);
          tester.view.physicalSize = destination;
        } else {
          tester.view.physicalSize = destination;
          if (order == 'geometry in earlier frame') {
            await tester.pumpAndSettle();
          }
          _inset(tester, 0);
        }
        await tester.pumpAndSettle();
        _expectEditor(h);

        // Zero can span many frames. A stale inherited snapshot must not
        // overwrite platform metrics or end rotation protection.
        h.staleMediaQuery.value = true;
        await tester.pump(const Duration(seconds: 3));
        tester.binding.handleMetricsChanged();
        await tester.pumpAndSettle();
        _expectEditor(h);
        _expectNoShow(tester);

        if (order == 'final geometry with fresh inset') {
          // Model both properties arriving in one engine notification.
          _geometryAndInset(
            tester,
            Size(destination.width, destination.height - 10),
            180,
          );
        } else {
          _inset(tester, 180);
        }
        await tester.pumpAndSettle();
        _expectEditor(h);
        _expectNoShow(tester);

        // The first intentional hide after recovery must still clear focus,
        // even though the inherited MediaQuery still claims an open IME.
        tester.testTextInput.hide();
        _inset(tester, 0);
        await tester.pumpAndSettle();
        expect(h.focus.hasFocus, isFalse);
        expect(
          h.controller.value,
          const TextEditingValue(text: _draft, selection: _selection),
        );
        _expectNoShow(tester);
      }, variant: _android);
    }
  }

  for (final geometry in ['resize', 'pixel ratio']) {
    testWidgets('viewport $geometry is not a keyboard dismissal', (
      tester,
    ) async {
      final h = await _mount(tester);
      await _open(tester, h);
      if (geometry == 'resize') {
        tester.view.physicalSize = const Size(500, 800);
      } else {
        tester.view.devicePixelRatio = 1.25;
      }
      _inset(tester, 0);
      await tester.pumpAndSettle();
      _expectEditor(h);
      _inset(tester, 200);
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      _inset(tester, 0);
      await tester.pumpAndSettle();
      expect(h.focus.hasFocus, isFalse);
      _expectNoShow(tester);
    }, variant: _android);
  }

  testWidgets('rotation with retained IME ends on stable positive metrics', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _open(tester, h);
    tester.view.physicalSize = _landscape;
    await tester.pumpAndSettle();
    _expectEditor(h);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    _inset(tester, 0);
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isFalse);
    _expectNoShow(tester);
  }, variant: _android);

  testWidgets('fresh positive metric cancels an earlier queued zero', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _open(tester, h);
    _inset(tester, 0);
    _inset(tester, 200);
    await tester.pumpAndSettle();
    _expectEditor(h);
    tester.testTextInput.hide();
    _inset(tester, 0);
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isFalse);
    _expectNoShow(tester);
  }, variant: _android);

  for (final dismiss in ['Back', 'swipe', 'floating keyboard']) {
    testWidgets(
      '$dismiss without geometry change remains dismissed on resume',
      (tester) async {
        final h = await _mount(tester);
        await _open(tester, h);
        if (dismiss == 'swipe') {
          for (final inset in [220.0, 110.0, 30.0]) {
            _inset(tester, inset);
            await tester.pump();
          }
        }
        tester.testTextInput.hide();
        _inset(tester, 0);
        await tester.pumpAndSettle();
        expect(h.focus.hasFocus, isFalse);
        tester.view.physicalSize = _landscape;
        await tester.pumpAndSettle();
        _pause(tester);
        _resume(tester);
        final restored = _requestRestore(tester);
        await tester.pumpAndSettle();
        expect(await restored, isFalse);
        expect(h.focus.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(h.controller.text, _draft);
        _expectNoShow(tester);
      },
      variant: _android,
    );
  }

  for (final dismiss in ['connection closed', 'page Back', 'tap outside']) {
    testWidgets(
      '$dismiss cancels rotation protection while IME inset is zero',
      (tester) async {
        final h = await _mount(tester);
        await _open(tester, h);
        tester.view.physicalSize = _landscape;
        _inset(tester, 0);
        await tester.pumpAndSettle();
        _expectEditor(h);
        if (dismiss == 'connection closed') {
          tester.testTextInput.closeConnection();
        } else if (dismiss == 'page Back') {
          // Exercise the existing page's explicit unfocus behavior while a
          // rotation is pending (Back is handled by KeyboardDismissPopScope).
          _inset(tester, 180);
          await tester.pumpAndSettle();
          // PopScope's inferred generic type is not an exact match for the
          // raw type used by find.byType. Match every PopScope instantiation.
          final pop = tester.widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope),
          );
          expect(pop.canPop, isFalse);
          expect(await h.navigator.currentState!.maybePop(), isTrue);
        } else {
          // Touch onTapOutside is deliberately explicit in GlassSearchBar.
          await tester.tapAt(const Offset(200, 330));
        }
        await tester.pumpAndSettle();
        expect(find.byType(GlassSearchBar), findsOneWidget);
        expect(h.focus.hasFocus, isFalse);
        tester.testTextInput.hide();
        _inset(tester, 0);
        tester.view.physicalSize = _portrait;
        await tester.pumpAndSettle();
        expect(find.byType(GlassSearchBar), findsOneWidget);
        expect(h.focus.hasFocus, isFalse);
        expect(h.controller.text, _draft);
        _expectNoShow(tester);
      },
      variant: _android,
    );
  }

  for (final focused in [false, true]) {
    testWidgets('rotation with already zero inset focused=$focused', (
      tester,
    ) async {
      final h = await _mount(tester);
      if (focused) {
        // An editor can be focused with a floating/hardware keyboard and no
        // bottom inset. Rotation must not create a request to show an IME.
        await tester.enterText(find.byType(TextField).first, _draft);
        tester.testTextInput.hide();
      }
      tester.testTextInput.log.clear();
      tester.view.physicalSize = _landscape;
      await tester.pumpAndSettle();
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      expect(h.focus.hasFocus, focused);
      expect(tester.testTextInput.isVisible, isFalse);
      _expectNoShow(tester);
      _inset(tester, 180);
      await tester.pumpAndSettle();
      _inset(tester, 0);
      await tester.pumpAndSettle();
      expect(h.focus.hasFocus, isFalse);
    }, variant: _android);
  }

  for (final hide in ['offstage', 'new route', 'other editor', 'dispose']) {
    testWidgets('queued rotation metrics cannot revive search after $hide', (
      tester,
    ) async {
      final h = await _mount(tester);
      await _open(tester, h);
      // Leave a dismissal queued, then transfer ownership before its callback.
      _inset(tester, 0);
      tester.view.physicalSize = _landscape;
      final nextFocus = hide == 'new route' ? h.routeFocus : h.other;
      if (hide == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        if (hide == 'offstage') {
          h.offstage.value = true;
          await tester.pump();
        } else if (hide == 'new route') {
          unawaited(
            h.navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    Scaffold(body: TextField(focusNode: h.routeFocus)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        nextFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(nextFocus.hasPrimaryFocus, isTrue);
        tester.testTextInput.log.clear();
      }
      _inset(tester, 180);
      await tester.pumpAndSettle();
      _inset(tester, 0);
      await tester.pumpAndSettle();
      expect(h.focus.hasFocus, isFalse);
      if (hide != 'dispose') expect(nextFocus.hasPrimaryFocus, isTrue);
      _expectNoShow(tester);
    }, variant: _android);
  }

  for (final inactiveOnly in [false, true]) {
    testWidgets(
      'rotation preserves first app-switch restore inactive=$inactiveOnly',
      (tester) async {
        final h = await _mount(tester);
        await _open(tester, h);
        _pause(tester, inactiveOnly: inactiveOnly);
        tester.testTextInput.hide();
        tester.view.physicalSize = _landscape;
        _resume(tester);
        // A stale positive metric must not retire the existing resume guard.
        tester.binding.handleMetricsChanged();
        await tester.pumpAndSettle();
        _inset(tester, 0);
        await tester.pump(const Duration(milliseconds: 600));
        _expectEditor(h);
        _expectNoShow(tester);
        final restored = _requestRestore(tester);
        await tester.pumpAndSettle();
        expect(await restored, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        _expectEditor(h);
        _inset(tester, 180);
        await tester.pumpAndSettle();
        tester.testTextInput.log.clear();
        tester.testTextInput.hide();
        _inset(tester, 0);
        await tester.pumpAndSettle();
        expect(h.focus.hasFocus, isFalse);
        final duplicate = _requestRestore(tester);
        await tester.pumpAndSettle();
        expect(await duplicate, isFalse);
        _expectNoShow(tester);
      },
      variant: _android,
    );
  }

  testWidgets(
    'background geometry does not outlive the existing resume guard',
    (tester) async {
      final h = await _mount(tester);
      await _open(tester, h);
      _pause(tester);
      tester.view.physicalSize = _landscape;
      _resume(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      tester.testTextInput.hide();
      _inset(tester, 0);
      await tester.pumpAndSettle();
      expect(h.focus.hasFocus, isFalse);
      _expectNoShow(tester);
    },
    variant: _android,
  );
}

Future<_Harness> _mount(WidgetTester tester, {bool landscape = false}) async {
  _resume(tester);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = landscape ? _landscape : _portrait;
  _inset(tester, 0);
  addTearDown(tester.view.reset);
  addTearDown(() => _resume(tester));
  final h = _Harness();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    h.focus.dispose();
    h.other.dispose();
    h.routeFocus.dispose();
    h.controller.dispose();
    h.offstage.dispose();
    h.staleMediaQuery.dispose();
    expect(tester.takeException(), isNull);
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: h.navigator,
      builder: (_, child) => KeyboardResumeScope(child: child!),
      home: KeyboardDismissPopScope(
        child: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: h.offstage,
                builder: (_, offstage, child) =>
                    Offstage(offstage: offstage, child: child),
                child: ValueListenableBuilder<bool>(
                  valueListenable: h.staleMediaQuery,
                  builder: (context, stale, child) => MediaQuery(
                    data: stale
                        ? const MediaQueryData(
                            size: _portrait,
                            viewInsets: EdgeInsets.only(bottom: 280),
                          )
                        : MediaQuery.of(context),
                    child: child!,
                  ),
                  child: GlassSearchBar(
                    hintText: 'Search',
                    focusNode: h.focus,
                    controller: h.controller,
                  ),
                ),
              ),
              TextField(key: _otherKey, focusNode: h.other),
            ],
          ),
        ),
      ),
    ),
  );
  return h;
}

Future<void> _open(WidgetTester tester, _Harness h) async {
  await tester.enterText(find.byType(TextField).first, _draft);
  h.controller.selection = _selection;
  _inset(tester, 280);
  await tester.pumpAndSettle();
  _expectEditor(h);
  tester.testTextInput.log.clear();
}

void _inset(WidgetTester tester, double bottom) {
  tester.view.viewInsets = FakeViewPadding(bottom: bottom);
}

void _geometryAndInset(WidgetTester tester, Size size, double bottom) {
  // TestFlutterView setters each send a notification. Temporarily suppress
  // dispatch to model an engine event that changes both values atomically.
  final dispatcher = tester.view.platformDispatcher;
  dispatcher.onMetricsChanged = null;
  try {
    tester.view.physicalSize = size;
    _inset(tester, bottom);
  } finally {
    dispatcher.onMetricsChanged = tester.binding.handleMetricsChanged;
  }
  tester.binding.handleMetricsChanged();
}

void _expectEditor(_Harness h) {
  expect(h.focus.hasPrimaryFocus, isTrue);
  expect(h.controller.text, _draft);
  expect(h.controller.selection, _selection);
}

void _expectNoShow(WidgetTester tester) {
  expect(
    tester.testTextInput.log.where((call) => call.method == 'TextInput.show'),
    isEmpty,
  );
}

void _pause(WidgetTester tester, {bool inactiveOnly = false}) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  if (inactiveOnly) return;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
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

Future<bool> _requestRestore(WidgetTester tester) {
  final result = Completer<bool>();
  const codec = StandardMethodCodec();
  tester.binding.channelBuffers.push(
    _resumeChannel.name,
    codec.encodeMethodCall(
      MethodCall('restoreFocusedInput', {
        'deadlineMs': DateTime.now().millisecondsSinceEpoch + 900,
      }),
    ),
    (reply) => result.complete(codec.decodeEnvelope(reply!) == true),
  );
  return result.future;
}

class _Harness {
  final focus = FocusNode();
  final other = FocusNode();
  final routeFocus = FocusNode();
  final controller = TextEditingController();
  final navigator = GlobalKey<NavigatorState>();
  final offstage = ValueNotifier(false);
  final staleMediaQuery = ValueNotifier(false);
}
