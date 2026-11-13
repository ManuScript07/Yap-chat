import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/app/chat_navigation_coordinator.dart';
import 'package:yap_chat/features/chat/bloc/voice_recorder_cubit.dart';
import 'package:yap_chat/features/chat/view/chat_composer_focus_controller.dart';
import 'package:yap_chat/features/chat/widgets/chat_pop_scope.dart';
import 'package:yap_chat/features/chats/data/data.dart';

void main() {
  testWidgets(
    'system Back with keyboard open dismisses input without leaving chat',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final screen = GlobalKey<_ScopeHarnessState>();
      await _mount(tester, nav, screen);
      await tester.enterText(find.byType(TextField), 'draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await nav.currentState!.maybePop();
      await tester.pump();
      expect(find.text('chat'), findsOneWidget);
      expect(screen.currentState!.focus.focusNode.hasFocus, isFalse);
      expect(screen.currentState!.exitCalls, 0);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump();
      await nav.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header exit pops once even while keyboard inset remains nonzero',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final screen = GlobalKey<_ScopeHarnessState>();
      await _mount(tester, nav, screen);
      await tester.enterText(find.byType(TextField), 'draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final state = screen.currentState!;
      await tester.tap(find.text('header-back'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('chat'), findsNothing);
      expect(state.exitCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final voice in [
    const VoiceRecorderState(),
    const VoiceRecorderState(status: VoiceRecorderStatus.preview),
    const VoiceRecorderState(status: VoiceRecorderStatus.recording),
    const VoiceRecorderState(isStarting: true),
  ]) {
    testWidgets(
      'system Back preserves recording guard: ${voice.status} starting=${voice.isStarting}',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final screen = GlobalKey<_ScopeHarnessState>();
        final finish = Completer<void>();
        await _mount(tester, nav, screen, voice: voice, finish: finish.future);
        final needsFinishing =
            voice.status == VoiceRecorderStatus.recording || voice.isStarting;
        unawaited(nav.currentState!.maybePop());
        await tester.pump();
        if (needsFinishing) {
          expect(find.text('chat'), findsOneWidget);
          expect(screen.currentState!.exitCalls, 1);
        }
        finish.complete();
        await tester.pumpAndSettle();
        expect(find.text('home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('repeated header exit waits for one recording finalization', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final screen = GlobalKey<_ScopeHarnessState>();
    final finish = Completer<void>();
    await _mount(
      tester,
      nav,
      screen,
      voice: const VoiceRecorderState(status: VoiceRecorderStatus.recording),
      finish: finish.future,
    );
    await tester.tap(find.text('header-back'));
    await tester.tap(find.text('header-back'));
    expect(screen.currentState!.exitCalls, 1);
    finish.complete();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'push coordinator opens, replaces and deduplicates routes with a focused keyboard',
    (tester) async {
      final first = GlobalKey<_ScopeHarnessState>();
      final router = _TestRouter(first);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router.config()),
      );
      await tester.pumpAndSettle();
      var loads = 0;
      final errors = <Object>[];
      final coordinator = ChatNavigationCoordinator(
        loadChat: (id) async {
          loads++;
          return _chat(id);
        },
        navigateToChat: (chat) async {
          final route = PageRouteInfo<void>(chat.id);
          if (router.current.name == 'first' ||
              router.current.name == 'second') {
            unawaited(router.popAndPush(route));
          } else {
            unawaited(router.push(route));
          }
          await WidgetsBinding.instance.endOfFrame;
        },
        isConversationVisible: (id) => router.current.name == id,
        isActive: () => true,
        onError: (error, _, _) => errors.add(error),
        waitForFrame: () async {},
      );
      var open = coordinator.openById('first');
      await tester.pumpAndSettle();
      await open;
      expect(router.stack.map((page) => page.name), ['home', 'first']);
      await tester.enterText(find.byType(TextField), 'draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(
        tester
            .widget<PopScope>(
              find.descendant(
                of: find.byType(ChatPopScope),
                matching: find.byWidgetPredicate(
                  (widget) => widget is PopScope,
                ),
              ),
            )
            .canPop,
        isFalse,
      );
      open = coordinator.openById('second');
      await tester.pumpAndSettle();
      await open;
      expect(router.stack.map((page) => page.name), ['home', 'second']);
      await coordinator.openById('second');
      expect(loads, 2);
      expect(router.stack.length, 2);
      expect(errors, isEmpty);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump();
      await tester.tap(find.text('header-back'));
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.name), ['home']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  GlobalKey<NavigatorState> nav,
  GlobalKey<_ScopeHarnessState> screen, {
  VoiceRecorderState voice = const VoiceRecorderState(),
  Future<void>? finish,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('home')),
    ),
  );
  unawaited(
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ScopeHarness(key: screen, voice: voice, finish: finish),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ScopeHarness extends StatefulWidget {
  const _ScopeHarness({
    super.key,
    this.voice = const VoiceRecorderState(),
    this.finish,
  });
  final VoiceRecorderState voice;
  final Future<void>? finish;
  @override
  State<_ScopeHarness> createState() => _ScopeHarnessState();
}

class _ScopeHarnessState extends State<_ScopeHarness> {
  final focus = ChatComposerFocusController();
  bool allowPop = false;
  bool exiting = false;
  int exitCalls = 0;
  Future<void> exit() async {
    if (exiting) return;
    exiting = true;
    exitCalls++;
    focus.dismiss();
    await widget.finish;
    if (!mounted) return;
    setState(() => allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatPopScope(
    voiceState: widget.voice,
    allowPop: allowPop,
    onExit: exit,
    child: Scaffold(
      body: Column(
        children: [
          const Text('chat'),
          TextButton(onPressed: exit, child: const Text('header-back')),
          TextField(focusNode: focus.focusNode),
        ],
      ),
    ),
  );
}

class _TestRouter extends RootStackRouter {
  _TestRouter(this.first);
  final GlobalKey<_ScopeHarnessState> first;
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'home',
      path: '/',
      initial: true,
      builder: (_, _) => const Scaffold(body: Text('home')),
    ),
    NamedRouteDef(
      name: 'first',
      path: '/first',
      builder: (_, _) => _ScopeHarness(key: first),
    ),
    NamedRouteDef(
      name: 'second',
      path: '/second',
      builder: (_, _) => const _ScopeHarness(),
    ),
  ];
}

Chat _chat(String id) => Chat(
  id: id,
  userName: id,
  lastMessage: '',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);
