import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/chat_composer_focus_controller.dart';
import 'package:yap_chat/features/chat/widgets/message_actions_bottom_sheet.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/widgets/message_input_bar.dart';

void main() {
  for (final initiallyOpen in [false, true]) {
    testWidgets(
      'menu restores keyboard only if it was visible: $initiallyOpen',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final screen = GlobalKey<_ComposerHarnessState>();
        await tester.pumpWidget(_app(nav, _ComposerHarness(key: screen)));
        await tester.enterText(find.byType(TextField), 'draft');
        final text = tester.widget<TextField>(find.byType(TextField));
        text.controller!.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        tester.view.viewInsets = FakeViewPadding(
          bottom: initiallyOpen ? 280 : 0,
        );
        addTearDown(tester.view.resetViewInsets);
        if (!initiallyOpen) tester.testTextInput.hide();
        await tester.pump();
        // This models Android Back: the IME is hidden, but focus/cursor remain.
        expect(screen.currentState!.focus.focusNode.hasFocus, isTrue);
        await tester.tap(find.text('menu'));
        await tester.pumpAndSettle();
        expect(screen.currentState!.focus.focusNode.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        tester.view.viewInsets = const FakeViewPadding();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        await screen.currentState!.menuOperation;
        expect(screen.currentState!.focus.focusNode.hasFocus, initiallyOpen);
        expect(tester.testTextInput.isVisible, initiallyOpen);
        expect(text.controller!.text, 'draft');
        expect(
          text.controller!.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('profile return never opens keyboard: $initiallyOpen', (
      tester,
    ) async {
      final nav = GlobalKey<NavigatorState>();
      final screen = GlobalKey<_ComposerHarnessState>();
      await tester.pumpWidget(_app(nav, _ComposerHarness(key: screen)));
      await tester.enterText(find.byType(TextField), 'keep this draft');
      tester.view.viewInsets = FakeViewPadding(bottom: initiallyOpen ? 280 : 0);
      addTearDown(tester.view.resetViewInsets);
      if (!initiallyOpen) tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('profile'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(screen.currentState!.focus.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep this draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('navigation invalidates a pending menu restoration', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final screen = GlobalKey<_ComposerHarnessState>();
    await tester.pumpWidget(_app(nav, _ComposerHarness(key: screen)));
    await tester.enterText(find.byType(TextField), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    final state = screen.currentState!;
    final completed = Completer<void>();
    final operation = state.focus.suspendForMenu(
      state.context,
      () => completed.future,
    );
    // Profile/push navigation while the menu closes invalidates restoration.
    state.focus.dismiss();
    completed.complete();
    await tester.pumpAndSettle();
    await operation;
    expect(state.focus.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposed chat cannot restore focus after its menu completes', (
    tester,
  ) async {
    final screen = GlobalKey<_ComposerHarnessState>();
    await tester.pumpWidget(_app(GlobalKey(), _ComposerHarness(key: screen)));
    await tester.enterText(find.byType(TextField), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    final state = screen.currentState!;
    final completed = Completer<void>();
    final operation = state.focus.suspendForMenu(
      state.context,
      () => completed.future,
    );
    await tester.pumpWidget(const SizedBox());
    completed.complete();
    await operation;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final external in [false, true]) {
    testWidgets(
      'reply intentionally opens keyboard with external focus=$external',
      (tester) async {
        final node = FocusNode();
        addTearDown(node.dispose);
        final reply = ValueNotifier<String?>(null);
        addTearDown(reply.dispose);
        await tester.pumpWidget(
          _app(
            GlobalKey(),
            ValueListenableBuilder<String?>(
              valueListenable: reply,
              builder: (_, id, _) => MessageInputBar(
                focusNode: external ? node : null,
                replyToMessageId: id,
                onSend: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        reply.value = 'message';
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        if (external) expect(node.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
        // The input must not dispose a focus node supplied by its owner.
        node.addListener(() {});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sending preserves composer focus and clears only text', (
    tester,
  ) async {
    final sent = <String>[];
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(GlobalKey(), MessageInputBar(focusNode: node, onSend: sent.add)),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(sent, ['hello']);
    expect(node.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _app(GlobalKey<NavigatorState> nav, Widget body) => MaterialApp(
  navigatorKey: nav,
  theme: ThemeData(platform: TargetPlatform.android),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

class _ComposerHarness extends StatefulWidget {
  const _ComposerHarness({super.key});
  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  final focus = ChatComposerFocusController();
  Future<MessageAction?>? menuOperation;

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () {
          menuOperation = focus.suspendForMenu(
            context,
            () => showMessageActionsBottomSheet(
              context,
              message: ChatMessage(
                id: 'm',
                chatId: 'c',
                senderId: 'peer',
                text: 'hello',
                timestamp: DateTime(2026),
                isMine: false,
              ),
            ),
          );
        },
        child: const Text('menu'),
      ),
      TextButton(
        onPressed: () {
          focus.dismiss();
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('profile-page')),
              ),
            ),
          );
        },
        child: const Text('profile'),
      ),
      // The production composer also sees zero IME insets. Visibility must be
      // read from the outer View, not from this overridden MediaQuery.
      MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: MessageInputBar(focusNode: focus.focusNode, onSend: (_) {}),
      ),
    ],
  );
}
