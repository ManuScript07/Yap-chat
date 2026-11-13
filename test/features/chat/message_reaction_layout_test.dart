import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/animated_reaction_section.dart';
import 'package:yap_chat/features/chat/widgets/audio_message_content.dart';
import 'package:yap_chat/features/chat/widgets/message_actions_bottom_sheet.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/features/chat/widgets/message_media_grid.dart';
import 'package:yap_chat/features/chat/widgets/message_reactions.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';
import 'package:yap_chat/ui/ui.dart';

const _reactions = MessageReactionState(
  version: 2,
  reactions: [
    MessageReaction(userId: 'peer', code: ReactionCode.heart, position: 1),
    MessageReaction(userId: 'me', code: ReactionCode.heart, position: 2),
  ],
);

ChatMessage _message(MessageType type, bool mine) => ChatMessage(
  id: 'message',
  chatId: 'chat',
  senderId: mine ? 'me' : 'peer',
  text: type == MessageType.text ? 'Hi' : '',
  timestamp: DateTime(2026, 1, 1, 12, 34),
  isMine: mine,
  type: type,
  mediaUrls: type == MessageType.image
      ? const ['missing-local-photo.jpg']
      : const [],
  audioUrl: type == MessageType.audio ? 'local-voice.m4a' : null,
  audioDuration: const Duration(seconds: 8),
  latitude: 10,
  longitude: 20,
);

Widget _app(Widget child, {double textScale = 1}) =>
    BlocProvider<AuthBloc>.value(
      value: _Auth(),
      child: RepositoryProvider<IAudioPlayerRepository>.value(
        value: _Audio(),
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.dark(primary: AppColors.brandPrimary),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  for (final mine in [false, true]) {
    for (final reply in [false, true]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          'text mine=$mine reply=$reply scale=$scale keeps one bottom-right status through reaction animation',
          (tester) async {
            final message = ValueNotifier(
              _message(MessageType.text, mine).copyWith(
                replyTo: reply
                    ? const MessageReply(
                        messageId: 'original',
                        senderId: 'peer',
                        isMine: false,
                        type: MessageType.text,
                        text: 'Original',
                      )
                    : null,
              ),
            );
            addTearDown(message.dispose);
            await tester.pumpWidget(
              _app(
                ValueListenableBuilder<ChatMessage>(
                  valueListenable: message,
                  builder: (_, m, _) => MessageBubble(
                    message: m,
                    initialAnimationProgress: 1,
                    maxWidth: 240,
                    peerName: 'Peer',
                  ),
                ),
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            final timeElement = tester.element(find.text('12:34'));
            final bubble = find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(22),
              ),
            );
            final body = find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.textSpan?.toPlainText().startsWith('Hi') == true,
            );
            final bodyOffset =
                tester.getRect(body).top - tester.getRect(bubble).top;
            void checkFrame() {
              expect(find.text('12:34'), findsOneWidget);
              expect(tester.element(find.text('12:34')), same(timeElement));
              final rect = tester.getRect(bubble);
              final status = tester.getRect(
                find
                    .ancestor(
                      of: find.text('12:34'),
                      matching: find.byType(Row),
                    )
                    .first,
              );
              expect(status.right, closeTo(rect.right - 12, .1));
              expect(status.bottom, closeTo(rect.bottom - 12, .1));
              expect(
                tester.getRect(body).top - rect.top,
                closeTo(bodyOffset, .1),
              );
              expect(tester.takeException(), isNull);
            }

            checkFrame();
            for (final state in [
              _reactions,
              _reactions.withChoice('me', ReactionCode.fire),
              const MessageReactionState(),
            ]) {
              message.value = message.value.copyWith(reactionState: state);
              await tester.pump();
              checkFrame();
              for (var i = 0; i < 36; i++) {
                await tester.pump(const Duration(milliseconds: 8));
                checkFrame();
              }
            }
          },
        );
      }
    }
  }
  for (final mine in [false, true]) {
    for (final maxWidth in [180.0, 240.0, 300.0]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          'tiny text mine=$mine width=$maxWidth scale=$scale handles two-to-one reactions on every frame',
          (tester) async {
            final state = ValueNotifier(_message(MessageType.text, mine));
            addTearDown(state.dispose);
            await tester.pumpWidget(
              _app(
                ValueListenableBuilder<ChatMessage>(
                  valueListenable: state,
                  builder: (_, message, _) => MessageBubble(
                    message: message,
                    initialAnimationProgress: 1,
                    maxWidth: maxWidth,
                    peerName: 'Peer',
                  ),
                ),
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            final two = _reactions.withChoice('me', ReactionCode.fire);
            // Exercise both removals: the outgoing pill can be first or last.
            // Also cover merging, where an outgoing avatar changes group.
            for (final next in [
              two.withChoice('me', null),
              two.withChoice('peer', null),
              _reactions,
            ]) {
              state.value = state.value.copyWith(reactionState: two);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              state.value = state.value.copyWith(reactionState: next);
              await tester.pump();
              expect(tester.takeException(), isNull);
              for (var frame = 0; frame < 36; frame++) {
                await tester.pump(const Duration(milliseconds: 8));
                expect(tester.takeException(), isNull, reason: 'frame $frame');
              }
              state.value = state.value.copyWith(
                reactionState: const MessageReactionState(),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
    testWidgets(
      'single-line reply mine=$mine keeps time at bubble right before and after reactions',
      (tester) async {
        final state = ValueNotifier(
          _message(MessageType.text, mine).copyWith(
            replyTo: const MessageReply(
              messageId: 'original',
              senderId: 'peer',
              isMine: false,
              type: MessageType.text,
              text: 'Original message',
            ),
          ),
        );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder<ChatMessage>(
              valueListenable: state,
              builder: (_, message, _) => MessageBubble(
                message: message,
                initialAnimationProgress: 1,
                maxWidth: 300,
                peerName: 'Peer',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bubble = find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).borderRadius ==
                    BorderRadius.circular(22),
          ),
        );
        final bubbleRect = tester.getRect(bubble);
        void expectRight(Finder time) {
          final status = find
              .ancestor(of: time, matching: find.byType(Row))
              .first;
          expect(
            tester.getRect(status).right,
            closeTo(bubbleRect.right - 12, .1),
          );
        }

        expectRight(find.text('12:34'));
        state.value = state.value.copyWith(reactionState: _reactions);
        await tester.pumpAndSettle();
        expect(find.text('12:34'), findsOneWidget);
        expectRight(find.text('12:34'));
        expect(tester.getRect(bubble).width, bubbleRect.width);
        state.value = state.value.copyWith(
          reactionState: const MessageReactionState(),
        );
        await tester.pumpAndSettle();
        expectRight(find.text('12:34'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final type in MessageType.values) {
    for (final mine in [false, true]) {
      testWidgets(
        '$type mine=$mine preserves content geometry and insets reactions',
        (tester) async {
          final message = ValueNotifier(_message(type, mine));
          addTearDown(message.dispose);
          await tester.pumpWidget(
            _app(
              ValueListenableBuilder<ChatMessage>(
                valueListenable: message,
                builder: (_, m, _) => MessageBubble(
                  message: m,
                  initialAnimationProgress: 1,
                  maxWidth: 300,
                  peerName: 'Peer',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final content = switch (type) {
            MessageType.image => find.byType(MessageMediaGrid),
            MessageType.audio => find.byType(AudioMessageContent),
            MessageType.location => find.byIcon(Icons.location_on_rounded),
            MessageType.text => find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.textSpan?.toPlainText().startsWith('Hi') == true,
            ),
          };
          final before = tester.getSize(content);
          message.value = message.value.copyWith(reactionState: _reactions);
          await tester.pump();
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 40));
            expect(tester.takeException(), isNull);
          }
          expect(tester.getSize(content), before);
          final reaction = tester.getRect(find.byType(MessageReactions));
          final contentRect = tester.getRect(content);
          expect(reaction.top, greaterThanOrEqualTo(contentRect.bottom));
          if (type == MessageType.image) {
            expect(reaction.left - contentRect.left, closeTo(4, .1));
          }
          if (type == MessageType.audio) {
            expect(reaction.left - contentRect.left, closeTo(12, .1));
          }
          if (type == MessageType.location) {
            expect(reaction.left, closeTo(contentRect.left, .1));
          }
          if (type == MessageType.text) {
            final time = find.text('12:34');
            expect(time, findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(AnimatedReactionSection),
                matching: time,
              ),
              findsNothing,
            );
            expect(tester.getRect(time).top, greaterThan(contentRect.bottom));
            expect(tester.getRect(time).right, greaterThan(reaction.right));
          }
          message.value = message.value.copyWith(
            reactionState: const MessageReactionState(),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(content), before);
          expect(find.byType(MessageReactions), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'short text has no artificial 180px width and scaled status does not overlap reactions',
    (tester) async {
      final m = _message(MessageType.text, false).copyWith(
        reactionState: const MessageReactionState(
          reactions: [
            MessageReaction(
              userId: 'me',
              code: ReactionCode.heart,
              position: 1,
            ),
          ],
        ),
      );
      for (final scale in [1.0, 1.8]) {
        await tester.pumpWidget(
          _app(
            MessageBubble(
              message: m,
              initialAnimationProgress: 1,
              maxWidth: 230,
              peerName: 'Peer',
            ),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final section = tester.getSize(find.byType(AnimatedReactionSection));
        if (scale == 1) {
          expect(section.width + 24, lessThan(180));
        }
        final reaction = tester.getRect(find.byType(MessageReactions));
        final status = tester.getRect(
          find
              .ancestor(of: find.text('12:34'), matching: find.byType(Row))
              .first,
        );
        expect(reaction.overlaps(status), isFalse);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('narrow scaled text reserves and clips the status footer', (
    tester,
  ) async {
    final message = ValueNotifier(_message(MessageType.text, true));
    addTearDown(message.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<ChatMessage>(
          valueListenable: message,
          builder: (_, m, _) => MessageBubble(
            message: m,
            initialAnimationProgress: 1,
            maxWidth: 180,
            peerName: 'Peer',
          ),
        ),
        textScale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    for (final state in [_reactions, const MessageReactionState()]) {
      message.value = message.value.copyWith(reactionState: state);
      await tester.pump();
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final clip = find.descendant(
          of: find.byType(AnimatedReactionSection),
          matching: find.byWidgetPredicate(
            (w) => w is ClipRect && w.clipper != null,
          ),
        );
        expect(clip, findsOneWidget);
        final clipRect = tester
            .widget<ClipRect>(clip)
            .clipper!
            .getClip(tester.getSize(clip));
        final status = tester.getRect(
          find
              .ancestor(of: find.text('12:34'), matching: find.byType(Row))
              .first,
        );
        // At the start/end the reveal clips all content (zero-height clip).
        // Only a non-empty paint region needs to stay above the status.
        if (clipRect.height > 0) {
          expect(
            tester.getTopLeft(clip).dy + clipRect.bottom,
            lessThanOrEqualTo(status.top - 4 + .1),
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      if (state.reactions.isNotEmpty) {
        expect(
          tester.getSize(find.byType(AnimatedReactionSection)).height,
          greaterThan(38),
        );
      }
    }
  });

  testWidgets('landscape shows all actions and picker has no blue background', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext context;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final closed = showMessageActionsBottomSheet(
      context,
      message: _message(MessageType.text, false),
      onReaction: (_) {},
    );
    await tester.pumpAndSettle();
    for (final icon in [
      Icons.copy_rounded,
      Icons.reply_rounded,
      Icons.delete_outline_rounded,
    ]) {
      final rect = tester.getRect(find.byIcon(icon));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(300));
    }
    final strip = find
        .ancestor(
          of: find.byType(ReactionIcon).first,
          matching: find.byType(Material),
        )
        .first;
    expect(tester.widget<Material>(strip).color, Colors.transparent);
    await tester.tap(find.byType(ReactionIcon).first);
    await tester.pumpAndSettle();
    await closed;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'avatars move smoothly in chronological order and fade on removal',
    (tester) async {
      final state = ValueNotifier(
        _message(MessageType.text, true).copyWith(reactionState: _reactions),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<ChatMessage>(
            valueListenable: state,
            builder: (_, m, _) =>
                MessageReactions(message: m, currentUserId: 'me'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final peer = find.byKey(const ValueKey('peer'));
      final own = find.byKey(const ValueKey('me'));
      expect(
        tester.getTopLeft(own).dx - tester.getTopLeft(peer).dx,
        closeTo(15, .1),
      );
      final before = tester.getTopLeft(own).dx;
      state.value = state.value.copyWith(
        reactionState: _reactions.withChoice('peer', ReactionCode.fire),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final during = tester.getTopLeft(own).dx;
      await tester.pumpAndSettle();
      expect(during, greaterThan(before));
      expect(during, lessThan(tester.getTopLeft(own).dx));
      state.value = state.value.copyWith(
        reactionState: state.value.reactionState.withChoice('me', null),
      );
      await tester.pump();
      expect(own, findsOneWidget);
      expect(find.byKey(const ValueKey('pill:me')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(own, findsNothing);
      expect(find.byKey(const ValueKey('pill:me')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('own message pills use incoming color with peer transparency', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MessageReactions(
          message: _message(MessageType.text, true).copyWith(
            reactionState: _reactions.withChoice('me', ReactionCode.fire),
          ),
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? color(String id) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(ValueKey('pill:$id')),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color;
    expect(color('me'), AppColors.incomingBubble);
    expect(color('peer'), AppColors.incomingBubble.withValues(alpha: .25));
  });
  testWidgets(
    'closing text footer retains reaction until fade ends; rapid toggles stay safe',
    (tester) async {
      final message = ValueNotifier(
        _message(MessageType.text, false).copyWith(reactionState: _reactions),
      );
      addTearDown(message.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<ChatMessage>(
            valueListenable: message,
            builder: (_, m, _) => MessageBubble(
              message: m,
              initialAnimationProgress: 1,
              maxWidth: 300,
              peerName: 'Peer',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      message.value = message.value.copyWith(
        reactionState: const MessageReactionState(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(ReactionIcon), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(AnimatedReactionSection),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, greaterThan(0));
      expect(fade.opacity.value, lessThan(1));
      for (var i = 0; i < 5; i++) {
        message.value = message.value.copyWith(
          reactionState: i.isEven ? _reactions : const MessageReactionState(),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(ReactionIcon), findsOneWidget);
    },
  );
}

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(session: AuthSession(userId: 'me'));
  @override
  Stream<AuthState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements IAudioPlayerRepository {
  @override
  IAudioPlayerSession createSession() => _Session();
}

class _Session implements IAudioPlayerSession {
  @override
  Stream<AudioPlaybackSnapshot> get snapshots => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
