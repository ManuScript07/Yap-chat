import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/features/chat/widgets/message_actions_bottom_sheet.dart';
import 'package:yap_chat/features/chat/widgets/message_reactions.dart';
import 'package:yap_chat/features/chat/widgets/animated_reaction_section.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets('new reaction fades in, replacement does not restart opacity', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'changed',
      chatId: 'chat',
      senderId: 'peer',
      isMine: false,
      text: 'changed',
      timestamp: DateTime(2026),
    );
    final state = ValueNotifier(message);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<ChatMessage>(
            valueListenable: state,
            builder: (_, m, _) =>
                MessageReactions(message: m, currentUserId: 'me'),
          ),
        ),
      ),
    );
    state.value = message.copyWith(
      reactionState: const MessageReactionState(
        version: 1,
        reactions: [MessageReaction(userId: 'me', code: ReactionCode.heart)],
      ),
    );
    await tester.pump();
    Iterable<Opacity> opacities() => tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(MessageReactions),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacities().any((w) => w.opacity == 0), isTrue);
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacities().any((w) => w.opacity > 0 && w.opacity < 1), isTrue);
    await tester.pumpAndSettle();
    state.value = message.copyWith(
      reactionState: const MessageReactionState(
        version: 2,
        reactions: [MessageReaction(userId: 'me', code: ReactionCode.fire)],
      ),
    );
    await tester.pump();
    expect(opacities().every((w) => w.opacity == 1), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing reactions are opaque on first frame and remount', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'existing',
      chatId: 'chat',
      senderId: 'peer',
      isMine: false,
      text: 'existing',
      timestamp: DateTime(2026),
      reactionState: const MessageReactionState(
        version: 1,
        reactions: [MessageReaction(userId: 'me', code: ReactionCode.heart)],
      ),
    );
    for (var mount = 0; mount < 2; mount++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageReactions(
              key: ValueKey(mount),
              message: message,
              currentUserId: 'me',
            ),
          ),
        ),
      );
      final opacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(MessageReactions),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities, isNotEmpty);
      expect(opacities.every((w) => w.opacity == 1), isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  final message = ChatMessage(
    id: 'message',
    chatId: 'chat',
    senderId: 'peer',
    text: 'hello',
    timestamp: DateTime(2026),
    isMine: false,
  );
  final same = const MessageReactionState(
    version: 2,
    reactions: [
      MessageReaction(userId: 'me', code: ReactionCode.heart),
      MessageReaction(userId: 'peer', code: ReactionCode.heart),
    ],
  );
  testWidgets('same reactions merge into a pill with overlapping avatars', (
    tester,
  ) async {
    ReactionCode? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageReactions(
            message: message.copyWith(reactionState: same),
            currentUserId: 'me',
            onSelected: (c) => tapped = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReactionIcon), findsOneWidget);
    expect(find.byType(UserAvatar), findsNWidgets(2));
    final avatars = find.byType(UserAvatar);
    expect(
      tester.getTopLeft(avatars.last).dx - tester.getTopLeft(avatars.first).dx,
      15,
    );
    await tester.tap(find.byType(ReactionIcon));
    expect(tapped, ReactionCode.heart);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'add/remove animates height; replacement keeps height and entrance',
    (tester) async {
      final auth = _Auth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await auth.close();
      });
      final state = ValueNotifier(message);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<ChatMessage>(
                valueListenable: state,
                builder: (_, m, _) => MessageBubble(
                  message: m,
                  initialAnimationProgress: 1,
                  maxWidth: 300,
                  peerName: 'Peer',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester
          .getSize(find.byType(AnimatedReactionSection))
          .height;
      state.value = message.copyWith(reactionState: same);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final during = tester
          .getSize(find.byType(AnimatedReactionSection))
          .height;
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(AnimatedReactionSection)).height;
      expect(tester.takeException(), isNull, reason: 'adding reaction');
      expect(during, greaterThan(before));
      expect(during, lessThan(after));
      state.value = message.copyWith(
        reactionState: const MessageReactionState(
          version: 3,
          reactions: [
            MessageReaction(userId: 'me', code: ReactionCode.fire),
            MessageReaction(userId: 'peer', code: ReactionCode.heart),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AnimatedReactionSection)).height,
        after,
      );
      expect(tester.takeException(), isNull, reason: 'replacing reaction');
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byType(MessageBubble),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
      state.value = message;
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AnimatedReactionSection)).height,
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('double tap toggles heart and disabled bubbles cannot react', (
    tester,
  ) async {
    final choices = <bool>[];
    Widget screen(bool enabled) => MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          initialAnimationProgress: 1,
          maxWidth: 240,
          peerName: 'Peer',
          onReaction: enabled
              ? (code, toggle) {
                  expect(code, ReactionCode.heart);
                  choices.add(toggle);
                }
              : null,
        ),
      ),
    );
    await tester.pumpWidget(screen(true));
    final content = find.byWidgetPredicate(
      (w) => w is Text && w.textSpan?.toPlainText().startsWith('hello') == true,
    );
    await tester.tap(content);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(content);
    await tester.pumpAndSettle();
    expect(choices, [true]);
    await tester.pumpWidget(screen(false));
    await tester.tap(content);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(content);
    await tester.pumpAndSettle();
    expect(choices, [true]);
  });
  testWidgets(
    'reaction strip fits portrait and landscape outside the action sheet',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(760, 300)]) {
        await tester.binding.setSurfaceSize(size);
        late BuildContext page;
        ReactionCode? selected;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  page = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        final closed = showMessageActionsBottomSheet(
          page,
          message: message,
          onReaction: (c) => selected = c,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReactionIcon), findsNWidgets(6));
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is ReactionIcon && w.code == ReactionCode.mindBlown,
          ),
        );
        await tester.pumpAndSettle();
        await closed;
        expect(selected, ReactionCode.mindBlown);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'reply-style index navigation remains correct after reaction resize',
    (tester) async {
      final auth = _Auth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await auth.close();
      });
      final controller = ItemScrollController();
      final positions = ItemPositionsListener.create();
      final changed = ValueNotifier(false);
      addTearDown(changed.dispose);
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: changed,
                builder: (_, active, _) => ScrollablePositionedList.builder(
                  itemScrollController: controller,
                  itemPositionsListener: positions,
                  reverse: true,
                  itemCount: 180,
                  itemBuilder: (_, i) => MessageBubble(
                    key: ValueKey(i),
                    message: message.copyWith(
                      id: '$i',
                      reactionState: active && i % 3 == 0
                          ? same
                          : const MessageReactionState(),
                    ),
                    initialAnimationProgress: 1,
                    maxWidth: 240,
                    peerName: 'Peer',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      changed.value = true;
      await tester.pumpAndSettle();
      final scrolled = controller.scrollTo(
        index: 120,
        alignment: .4,
        duration: const Duration(milliseconds: 350),
      );
      await tester.pumpAndSettle();
      await scrolled;
      expect(
        positions.itemPositions.value.any(
          (p) =>
              p.index == 120 && p.itemLeadingEdge < 1 && p.itemTrailingEdge > 0,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(session: AuthSession(userId: 'me'));
  @override
  Stream<AuthState> get stream => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
