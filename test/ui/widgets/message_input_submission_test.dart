import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/widgets/widgets.dart';

void main() {
  testWidgets('accepted submission clears only after local enqueue', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final submitted = <String>[];
    final legacy = <String>[];
    final controller = await _mount(
      tester,
      onSend: legacy.add,
      onSubmit: (text) {
        submitted.add(text);
        return pending.future;
      },
    );
    await _enterDraft(tester, '  original draft  ');
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(submitted, ['original draft']);
    expect(legacy, isEmpty);
    expect(controller.text, '  original draft  ');
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(legacy, isEmpty);
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['rejected', 'async error', 'sync error']) {
    testWidgets('$outcome retains the original draft and permits retry', (
      tester,
    ) async {
      final pending = Completer<bool>();
      final submitted = <String>[];
      final legacy = <String>[];
      final controller = await _mount(
        tester,
        onSend: legacy.add,
        onSubmit: (text) {
          submitted.add(text);
          if (submitted.length > 1) return Future.value(true);
          if (outcome == 'sync error') throw StateError('enqueue failed');
          return pending.future;
        },
      );
      await _enterDraft(tester, '  keep this draft  ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(controller.text, '  keep this draft  ');
      if (outcome == 'rejected') {
        pending.complete(false);
      } else if (outcome == 'async error') {
        pending.completeError(StateError('enqueue failed'));
      }
      await tester.pumpAndSettle();
      expect(controller.text, '  keep this draft  ');
      expect(submitted, ['keep this draft']);
      expect(legacy, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(submitted, ['keep this draft', 'keep this draft']);
      expect(controller.text, isEmpty);
      expect(legacy, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('repeated taps submit once while pending', (tester) async {
    final pending = Completer<bool>();
    final submitted = <String>[];
    final controller = await _mount(
      tester,
      onSubmit: (text) {
        submitted.add(text);
        return submitted.length == 1 ? pending.future : Future.value(true);
      },
    );
    await _enterDraft(tester, 'first');
    await tester.tap(find.byIcon(Icons.send_rounded));
    // No frame between these taps: the guard must be set synchronously.
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(submitted, ['first']);
    expect(controller.text, 'first');

    pending.complete(true);
    await tester.pumpAndSettle();
    await _enterDraft(tester, 'second');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(submitted, ['first', 'second']);
    expect(controller.text, isEmpty);
  });

  for (final edit in ['new draft', 'away and back', 'whitespace only', 'empty']) {
    testWidgets('accepted submission preserves pending edit: $edit', (
      tester,
    ) async {
      final pending = Completer<bool>();
      final submitted = <String>[];
      var voiceCalls = 0;
      final controller = await _mount(
        tester,
        onVoiceRecord: () => voiceCalls++,
        onSubmit: (text) {
          submitted.add(text);
          return submitted.length == 1 ? pending.future : Future.value(true);
        },
      );
      await _enterDraft(tester, 'original');
      await tester.tap(find.byIcon(Icons.send_rounded));

      final String edited;
      switch (edit) {
        case 'away and back':
          await _enterDraft(tester, 'temporary');
          edited = 'original';
          break;
        case 'whitespace only':
          edited = ' original ';
          break;
        case 'empty':
          edited = '';
          break;
        default:
          edited = 'new draft';
      }
      await _enterDraft(tester, edited);
      await tester.tap(
        find.byIcon(edited.isEmpty ? Icons.mic_rounded : Icons.send_rounded),
      );
      expect(submitted, ['original']);
      expect(voiceCalls, 0);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(controller.text, edited);
      expect(tester.takeException(), isNull);

      if (edited.isNotEmpty) {
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        expect(submitted, ['original', edited.trim()]);
        expect(controller.text, isEmpty);
      }
    });
  }

  testWidgets('selection changes alone do not keep an accepted draft', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final controller = await _mount(tester, onSubmit: (_) => pending.future);
    await _enterDraft(tester, 'original');
    await tester.tap(find.byIcon(Icons.send_rounded));
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['accepted', 'rejected', 'error']) {
    testWidgets('dispose while pending is safe after $outcome', (tester) async {
      final pending = Completer<bool>();
      final legacy = <String>[];
      var submissions = 0;
      await _mount(
        tester,
        onSend: legacy.add,
        onSubmit: (_) {
          submissions++;
          return pending.future;
        },
      );
      await _enterDraft(tester, 'draft');
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());

      if (outcome == 'error') {
        pending.completeError(StateError('enqueue failed'));
      } else {
        pending.complete(outcome == 'accepted');
      }
      await tester.pumpAndSettle();
      expect(legacy, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy onSend receives trimmed text before immediate clearing', (
    tester,
  ) async {
    final sent = <String>[];
    final draftsAtSend = <String>[];
    late TextEditingController controller;
    controller = await _mount(
      tester,
      onSend: (text) {
        sent.add(text);
        draftsAtSend.add(controller.text);
      },
    );
    await _enterDraft(tester, '  legacy draft  ');
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sent, ['legacy draft']);
    expect(draftsAtSend, ['  legacy draft  ']);
    expect(controller.text, isEmpty);
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpAndSettle();
    await _enterDraft(tester, 'next');
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(sent, ['legacy draft', 'next']);
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank drafts keep voice and attachment actions', (tester) async {
    final submitted = <String>[];
    final legacy = <String>[];
    var voiceCalls = 0;
    var photoCalls = 0;
    final controller = await _mount(
      tester,
      onSend: legacy.add,
      onSubmit: (text) async {
        submitted.add(text);
        return true;
      },
      onVoiceRecord: () => voiceCalls++,
      onAddPhoto: () => photoCalls++,
    );
    await _enterDraft(tester, '   \n  ');
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.tap(find.byIcon(Icons.add));
    expect(submitted, isEmpty);
    expect(legacy, isEmpty);
    expect(controller.text, '   \n  ');
    expect(voiceCalls, 1);
    expect(photoCalls, 1);
  });
}

Future<TextEditingController> _mount(
  WidgetTester tester, {
  ValueChanged<String>? onSend,
  Future<bool> Function(String)? onSubmit,
  VoidCallback? onVoiceRecord,
  VoidCallback? onAddPhoto,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInputBar(
            onSend: onSend ?? (_) {},
            onSubmit: onSubmit,
            onVoiceRecord: onVoiceRecord,
            onAddPhoto: onAddPhoto,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<TextField>(find.byType(TextField)).controller!;
}

Future<void> _enterDraft(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}
