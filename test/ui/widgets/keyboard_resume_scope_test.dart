import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

const _codec = StandardMethodCodec();
const _channel = 'com.yapchat.app/keyboard_resume';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel(_channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      fail(
        'The restored baseline must not send a visibility probe: ${call.method}',
      );
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

  for (final search in [false, true]) {
    for (final staleInset in [false, true]) {
      testWidgets(
        'real editor restores on first return search=$search stale=$staleInset',
        (tester) async {
          final h = await _mount(tester, search: search);
          await tester.enterText(find.byType(TextField), 'preserved draft');
          h.controller(tester).selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 7,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          _pause(tester);
          tester.testTextInput.hide();
          if (!staleInset) {
            tester.view.viewInsets = const FakeViewPadding();
          }
          _resume(tester);
          final restored = _request(tester);
          await tester.pumpAndSettle();
          expect(await restored, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(h.focus.hasPrimaryFocus, isTrue);
          expect(h.controller(tester).text, 'preserved draft');
          expect(
            h.controller(tester).selection,
            const TextSelection(baseOffset: 2, extentOffset: 7),
          );
          // Repeated native events cannot show it again after a user hide.
          tester.testTextInput.hide();
          final duplicate = _request(tester);
          await tester.pumpAndSettle();
          expect(await duplicate, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          await h.dispose(tester);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }

    testWidgets('manual Back before app switch stays hidden search=$search', (
      tester,
    ) async {
      final h = await _mount(tester, search: search);
      await tester.enterText(find.byType(TextField), 'draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      _pause(tester);
      _resume(tester);
      final restored = _request(tester);
      await tester.pumpAndSettle();
      expect(await restored, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await h.dispose(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final cancel in [
    'profile',
    'unfocus',
    'dispose',
    'background',
    'expired',
  ]) {
    testWidgets('pending restore cannot revive editor after $cancel', (
      tester,
    ) async {
      final h = await _mount(tester);
      await tester.enterText(find.byType(TextField), 'draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      _pause(tester);
      tester.testTextInput.hide();
      _resume(tester);
      if (cancel == 'profile') {
        unawaited(
          h.navigator.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => const Scaffold()),
          ),
        );
        await tester.pumpAndSettle();
      } else if (cancel == 'unfocus') {
        h.focus.unfocus();
        await tester.pump();
      }
      final restored = _request(tester, expired: cancel == 'expired');
      if (cancel == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else if (cancel == 'background') {
        _pause(tester);
      }
      await tester.pumpAndSettle();
      expect(await restored, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await h.dispose(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('cold start never creates a keyboard request', (tester) async {
    final h = await _mount(tester);
    final restored = _request(tester);
    await tester.pumpAndSettle();
    expect(await restored, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await h.dispose(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('new focus owner is not confused with the background editor', (
    tester,
  ) async {
    final h = await _mount(tester, second: true);
    await tester.enterText(find.byType(TextField).first, 'old');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    _pause(tester);
    tester.testTextInput.hide();
    _resume(tester);
    await tester.showKeyboard(find.byKey(const ValueKey('second')));
    tester.testTextInput.hide();
    final restored = _request(tester);
    await tester.pumpAndSettle();
    expect(await restored, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await h.dispose(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool search = false,
  bool second = false,
}) async {
  _resume(tester);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() => _resume(tester));
  final h = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: h.navigator,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => KeyboardResumeScope(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            if (search)
              GlassSearchBar(hintText: 'Search', focusNode: h.focus)
            else
              MessageInputBar(focusNode: h.focus, onSend: (_) {}),
            if (second) const TextField(key: ValueKey('second')),
          ],
        ),
      ),
    ),
  );
  return h;
}

class _Harness {
  final focus = FocusNode();
  final navigator = GlobalKey<NavigatorState>();

  TextEditingController controller(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    focus.dispose();
    expect(tester.takeException(), isNull);
  }
}

Future<bool> _request(WidgetTester tester, {bool expired = false}) {
  final result = Completer<bool>();
  tester.binding.channelBuffers.push(
    _channel,
    _codec.encodeMethodCall(
      MethodCall('restoreFocusedInput', {
        'deadlineMs':
            DateTime.now().millisecondsSinceEpoch + (expired ? -1000 : 900),
      }),
    ),
    (reply) => result.complete(_codec.decodeEnvelope(reply!) == true),
  );
  return result.future;
}

void _pause(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
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
