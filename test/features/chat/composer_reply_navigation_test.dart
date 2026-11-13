import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/blocks/bloc/blocklist_cubit.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/chat_page.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/notifications/bloc/notifications_cubit.dart';
import 'package:yap_chat/features/presence/bloc/presence_cubit.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/blocks/mock_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/repositories/notifications/mock_push_notifications_repository.dart';
import 'package:yap_chat/repositories/presence/mock_presence_repository.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets('voice preview is restored after limit refusal and can retry', (
    tester,
  ) async {
    const audio = RecordedAudio(
      path: '/local/retained-voice.aac',
      duration: Duration(seconds: 3),
      waveform: [.1, .5, .2],
    );
    final media = _VoiceDraftMedia(audio);
    final messages = _AdmissionMessages();
    final chats = _AdmissionChats()..error = const ChatLimitReachedException();
    final router = await _mount(
      tester,
      messages,
      media: media,
      chats: chats,
      initialChat: Chat.directDraft(
        peerId: 'peer',
        peerUsername: 'peer',
        peerDisplayName: 'Peer',
      ),
    );
    final voice = tester
        .element(find.byType(VoiceRecorderBar))
        .read<VoiceRecorderCubit>();
    expect(voice.state.recordedAudio, audio);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _flushSubmissionFrames(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
    expect(messages.audio, isEmpty);
    expect(voice.state.status, VoiceRecorderStatus.preview);
    expect(voice.state.recordedAudio, audio);
    expect(media.removals, 0);
    await tester.tap(find.text(l10n.chatsLimitDismiss));
    await _flushSubmissionFrames(tester);
    chats.error = null;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _flushSubmissionFrames(tester);
    expect(messages.audio, [audio]);
    expect(voice.state.status, VoiceRecorderStatus.idle);
    expect(chats.created, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, router);
  });

  testWidgets('recovered camera image survives refusal and is enqueued once', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('chat-recovery-');
    final file = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
          '/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
        ),
      );
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      directory.deleteSync(recursive: true);
    });
    final media = _RecoveryMedia(file.path);
    final messages = _AdmissionMessages();
    final chats = _AdmissionChats()..error = const ChatLimitReachedException();
    final router = await _mount(
      tester,
      messages,
      chats: chats,
      media: media,
      initialChat: Chat.directDraft(
        peerId: 'peer',
        peerUsername: 'peer',
        peerDisplayName: 'Peer',
      ),
    );
    await _flushSubmissionFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final send = find.byType(FilledButton);
    await tester.tap(send);
    await _flushSubmissionFrames(tester);
    expect(chats.created, 1);
    expect(messages.images, isEmpty);
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
    await tester.tap(find.text(l10n.chatsLimitDismiss));
    await _flushSubmissionFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    chats.error = null;
    await tester.tap(send);
    await _flushSubmissionFrames(tester);
    expect(messages.images, [
      [file.path],
    ]);
    expect(chats.created, 2);
    expect(media.consumed, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, router);
  });

  for (final viewport in [const Size(390, 780), const Size(780, 390)]) {
    testWidgets(
      'real draft refuses limit without losing text and retries $viewport',
      (tester) async {
        await tester.binding.setSurfaceSize(viewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final messages = _AdmissionMessages();
        final chats = _AdmissionChats()
          ..error = const ChatLimitReachedException();
        final router = await _mount(
          tester,
          messages,
          chats: chats,
          initialChat: Chat.directDraft(
            peerId: 'peer',
            peerUsername: 'peer',
            peerDisplayName: 'Peer',
          ),
        );
        final field = find.descendant(
          of: find.byType(MessageInputBar),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'prepared message');
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        await _flushSubmissionFrames(tester);
        final diagnosticBloc = tester
            .element(find.byType(MessageInputBar))
            .read<ChatBloc>();
        expect(
          chats.created,
          1,
          reason: 'The real send button must dispatch draft admission',
        );
        expect(
          diagnosticBloc.state.chatLimitRefusalCount,
          1,
          reason: 'The typed refusal must reach the real page listener',
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        )!;
        expect(find.text(l10n.chatsLimitTitle), findsOneWidget);
        expect(controller.text, 'prepared message');
        expect(messages.sent, isEmpty);
        final bloc = tester
            .element(find.byType(MessageInputBar))
            .read<ChatBloc>();
        expect(bloc.state.status, ChatStatus.success);
        expect(bloc.state.resolvedChat, isNull);
        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        await _flushSubmissionFrames(tester);
        chats.error = null;
        chats.gate = Completer<Chat>();
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pump();
        await _flushSubmissionFrames(tester);
        await tester.enterText(field, 'next unsent draft');
        chats.gate!.complete(_admittedChat());
        await tester.pumpAndSettle();
        await _flushSubmissionFrames(tester);
        expect(messages.sent, ['prepared message']);
        expect(bloc.state.chatId, 'admitted');
        final current = tester.widget<TextField>(field).controller!;
        expect(
          identical(controller, current),
          true,
          reason: 'Draft promotion must preserve the composer subtree',
        );
        expect(current.text, 'next unsent draft');
        expect(chats.created, 2);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await _unmount(tester, router);
      },
    );
  }
  for (final (viewport, focused) in [
    (const Size(390, 780), false),
    (const Size(780, 390), false),
    (const Size(390, 780), true),
  ]) {
    testWidgets(
      'real chat preserves header, draft and layout across gallery $viewport focused=$focused',
      (tester) async {
        await tester.binding.setSurfaceSize(viewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const path = '/missing-chat-transition-photo.jpg';
        chatMediaAspectRatios.remember(path, .5);
        addTearDown(chatMediaAspectRatios.clear);
        final _ChatRepository repository = focused
            ? _BoundedRepository()
            : _ChatRepository();
        final photo = ChatMessage(
          id: 'photo',
          chatId: 'chat',
          senderId: 'peer',
          text: '',
          timestamp: DateTime(2026).add(const Duration(minutes: 500)),
          isMine: false,
          type: MessageType.image,
          mediaUrls: [path],
        );
        if (focused) {
          repository.window.complete([
            for (var i = 530; i >= 471; i--)
              i == 500 ? photo : _message('remote-$i', i),
          ]);
        } else {
          repository.messages
            ..clear()
            ..add(photo);
        }
        final router = await _mount(tester, repository);
        if (focused) {
          final bloc = BlocProvider.of<ChatBloc>(
            tester.element(find.byType(MessageBubble).first),
          );
          bloc.add(ChatReplySelected(photo));
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .descendant(
                  of: find.byType(ReplyComposerPreview),
                  matching: find.byType(GestureDetector),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(repository.windowCalls, 1);
        }
        await tester.enterText(find.byType(TextField), 'preserved draft');
        await tester.pumpAndSettle();
        final header = tester.element(find.byType(ChatAppBar));
        final topGradient = find
            .byWidgetPredicate(
              (widget) => widget is GradientOverlay && widget.isTop,
              skipOffstage: false,
            )
            .first;
        final gradientElement = tester.element(topGradient);
        expect(
          find.ancestor(
            of: topGradient,
            matching: find.byType(
              ChatMediaTransitionChrome,
              skipOffstage: false,
            ),
          ),
          findsNothing,
          reason: 'top shadow must not animate with controls',
        );
        final headerRect = tester.getRect(find.byType(ChatAppBar));
        final photoBubble = find.ancestor(
          of: find.byType(MessageMediaGrid),
          matching: find.byType(MessageBubble),
        );
        final messageRect = tester.getRect(photoBubble);
        final inputRect = tester.getRect(find.byType(MessageInputBar));
        final chrome = find.byWidgetPredicate(
          (widget) =>
              widget is ChatMediaTransitionChrome &&
              widget.region == ChatMediaChromeRegion.header,
          skipOffstage: false,
        );
        void expectStableHeader() => expect(
          find.ancestor(
            of: find.byType(ChatAppBar, skipOffstage: false),
            matching: find.byType(AnimatedOpacity, skipOffstage: false),
          ),
          findsNothing,
          reason: 'header has no independent fade',
        );
        final geometry = ChatMediaTransitionScope.maybeOf(
          tester.element(chrome),
        );
        expect(geometry!.headerRect, headerRect);
        expect(
          geometry.composerRect,
          tester.getRect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ChatMediaTransitionChrome &&
                  widget.region == ChatMediaChromeRegion.composer,
            ),
          ),
        );
        expect(geometry.composerRect!.contains(inputRect.center), isTrue);
        await tester.tap(
          find.descendant(
            of: find.byType(MessageMediaGrid),
            matching: find.byType(InkWell),
          ),
        );
        // The surrounding bubble also recognizes double-tap reactions.
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byType(ChatMediaGalleryPage), findsOneWidget);
        expectStableHeader();
        Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expectStableHeader();
        expect(tester.element(topGradient), same(gradientElement));
        expect(tester.element(find.byType(ChatAppBar)), same(header));
        await tester.pumpAndSettle();
        expectStableHeader();
        expect(tester.getRect(find.byType(ChatAppBar)), headerRect);
        expect(tester.getRect(photoBubble), messageRect);
        expect(tester.getRect(find.byType(MessageInputBar)), inputRect);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'preserved draft',
        );
        expect(repository.windowCalls, focused ? 1 : 0);
        expect(tester.takeException(), isNull);
        await _unmount(tester, router);
      },
    );
  }

  for (final keyboardRetained in [false, true]) {
    for (final staleEngine in [false, true]) {
      testWidgets(
        'composer follows recovered engine insets stale=$staleEngine retained=$keyboardRetained',
        (tester) async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          final router = await _mount(tester, _BoundedRepository());
          addTearDown(tester.view.resetViewInsets);
          addTearDown(() {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          });
          double composerOffset() => tester
              .widget<Positioned>(
                find
                    .ancestor(
                      of: find.byType(MessageInputBar),
                      matching: find.byType(Positioned),
                    )
                    .first,
              )
              .bottom!;

          await tester.enterText(find.byType(TextField), 'preserved draft');
          tester.view.viewInsets = FakeViewPadding(
            bottom: 300 * tester.view.devicePixelRatio,
          );
          await tester.pumpAndSettle();
          expect(composerOffset(), 300);
          final input = tester.widget<TextField>(find.byType(TextField));
          final originalFocus = input.focusNode!.hasFocus;
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
          // The real failure leaves FlutterView stale, not only MediaQuery.
          // A lifecycle notification alone cannot discover the hidden native IME.
          if (!staleEngine && !keyboardRetained) {
            tester.view.viewInsets = const FakeViewPadding();
          }
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

          expect(composerOffset(), staleEngine || keyboardRetained ? 300 : 0);
          // Android recovery publishes the authoritative hidden-IME metrics.
          // A visible keyboard is deliberately left untouched.
          if (!keyboardRetained) {
            tester.view.viewInsets = const FakeViewPadding();
          }
          await tester.pumpAndSettle();

          final actualViewInset = View.of(
            tester.element(find.byType(MessageInputBar)),
          ).viewInsets.bottom;
          final resumedOffset = composerOffset();
          expect(
            actualViewInset,
            keyboardRetained ? 300 * tester.view.devicePixelRatio : 0,
          );
          expect(tester.testTextInput.isVisible, keyboardRetained);
          expect(input.focusNode!.hasFocus, originalFocus);
          expect(resumedOffset, keyboardRetained ? 300 : 0);
          final restoredInput = tester.widget<TextField>(
            find.byType(TextField),
          );
          expect(restoredInput.focusNode, same(input.focusNode));
          expect(restoredInput.controller!.text, 'preserved draft');
          expect(
            tester
                .widget<PopScope>(
                  find.descendant(
                    of: find.byType(ChatPage),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is PopScope,
                    ),
                  ),
                )
                .canPop,
            !keyboardRetained,
          );
          tester.binding.handleMetricsChanged();
          await tester.pumpAndSettle();
          expect(composerOffset(), keyboardRetained ? 300 : 0);
          expect(input.focusNode!.hasFocus, originalFocus);
          expect(tester.takeException(), isNull);
          await _unmount(tester, router);
        },
      );
    }
  }

  for (final keyboardRetained in [false, true]) {
    testWidgets(
      'uncached reply window survives IME resume retained=$keyboardRetained',
      (tester) async {
        const nativeKeyboard = MethodChannel('com.yapchat.app/keyboard_resume');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(nativeKeyboard, (call) async {
          expect(call.method, 'shouldRestoreFocusedInput');
          return {
            'shouldRestore': !keyboardRetained,
            'imeVisible': keyboardRetained,
          };
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(nativeKeyboard, null),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repository = _BoundedRepository();
        final router = await _mount(tester, repository);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        final bloc = BlocProvider.of<ChatBloc>(
          tester.element(find.byType(MessageBubble).first),
        );
        final target = _message('remote-target-ime', -1000);
        bloc.add(ChatReplySelected(target));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ReplyComposerPreview),
            matching: find.text(target.text),
          ),
        );
        await tester.pump();
        repository.window.complete([
          for (var i = -970; i >= -1029; i--)
            i == -1000 ? target : _message('remote-$i', i),
        ]);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'draft in remote window',
        );
        tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        final bubble = find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message.id == target.id,
        );
        expect(bubble, findsOneWidget);
        final top = tester.getTopLeft(bubble).dy;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        if (!keyboardRetained) tester.testTextInput.hide();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        // Flutter still reports the old height until Android republishes it.
        if (!keyboardRetained) {
          tester.view.viewInsets = const FakeViewPadding();
        }
        final restored = _requestKeyboardResume(tester);
        await tester.pumpAndSettle();
        expect(await restored, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        expect(bubble, findsOneWidget);
        expect(tester.getTopLeft(bubble).dy, closeTo(top, 1));
        expect(BlocProvider.of<ChatBloc>(tester.element(bubble)), same(bloc));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'draft in remote window',
        );
        expect(repository.windowCalls, 1);
        expect(repository.olderCalls, 0);
        expect(tester.takeException(), isNull);
        await _unmount(tester, router);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final wheel in [false, true]) {
    testWidgets('recent down button follows user direction wheel=$wheel', (
      tester,
    ) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final list = find.byType(ScrollablePositionedList);
      final button = find.byKey(const ValueKey('scroll_to_bottom'));
      Future<void> move(double pixels) async {
        if (wheel) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(list),
              scrollDelta: Offset(0, -pixels),
            ),
          );
        } else {
          await tester.drag(list, Offset(0, pixels));
        }
        await tester.pumpAndSettle();
      }

      expect(button, findsNothing);
      await move(500);
      expect(button, findsNothing);
      await move(-80);
      expect(button, findsOneWidget);
      await move(35);
      expect(button, findsOneWidget);
      await move(100);
      expect(button, findsNothing);
      await move(-80);
      expect(button, findsOneWidget);
      if (!wheel) {
        final gesture = await tester.startGesture(tester.getCenter(list));
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        int firstVisible() => tester
            .widget<ScrollablePositionedList>(list)
            .itemPositionsNotifier!
            .itemPositions
            .value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .map((p) => p.index)
            .reduce((a, b) => a < b ? a : b);
        final first = firstVisible();
        await gesture.moveBy(const Offset(0, 1));
        await tester.pumpAndSettle();
        expect(firstVisible(), first);
        expect(button, findsOneWidget);
        await gesture.moveBy(const Offset(0, -1));
        await tester.pumpAndSettle();
        expect(firstVisible(), first);
        expect(button, findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      expect(repository.olderCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    });
  }

  testWidgets('focused down button follows user direction and new arrivals', (
    tester,
  ) async {
    final repository = _CachedDiagnosticRepository();
    repository.readGate = Completer<List<ChatMessage>?>()
      ..complete([for (var i = 530; i >= 471; i--) _message('$i', i)]);
    final router = await _mount(tester, repository);
    final bloc = BlocProvider.of<ChatBloc>(
      tester.element(find.byType(MessageBubble).first),
    );
    final target = _message('500', 500);
    bloc.add(ChatReplySelected(target));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ReplyComposerPreview),
        matching: find.text(target.text),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ScrollablePositionedList);
    final button = find.byKey(const ValueKey('scroll_to_bottom'));
    expect(button, findsNothing);
    await tester.drag(list, const Offset(0, -130));
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    await tester.drag(list, const Offset(0, 130));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'FOCUS_BUTTON afterReverse=${button.evaluate().length} focused=${tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition}',
    );
    expect(button, findsNothing);
    expect(
      tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
      isTrue,
    );
    final targetBubble = find.byWidgetPredicate(
      (w) => w is MessageBubble && w.message.id == target.id,
    );
    final top = tester.getTopLeft(targetBubble).dy;
    bloc.add(
      ChatMessagesReceived([
        _message('1000', 1000).copyWith(senderId: 'peer', isMine: false),
        ...repository.messages.take(59),
      ]),
    );
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(tester.getTopLeft(targetBubble).dy, closeTo(top, 0.01));
    // A small correction must not hide the control or its badge.
    await tester.drag(list, const Offset(0, 35));
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    await tester.drag(list, const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    await tester.drag(list, const Offset(0, -35));
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester, router);
  });

  testWidgets(
    'arrival badge survives history-to-recent handoff before bottom',
    (tester) async {
      final repository = _CachedDiagnosticRepository();
      repository.readGate = Completer<List<ChatMessage>?>()
        ..complete([for (var i = 980; i >= 921; i--) _message('$i', i)]);
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('950', 950);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pumpAndSettle();
      bloc.add(
        ChatMessagesReceived([
          _message('1000', 1000).copyWith(senderId: 'peer', isMine: false),
          ...repository.messages.take(59),
        ]),
      );
      await tester.pumpAndSettle();
      final list = find.byType(ScrollablePositionedList);
      final button = find.byKey(const ValueKey('scroll_to_bottom'));
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isTrue,
      );
      await tester.drag(list, const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isFalse,
      );
      expect(
        find.descendant(of: button, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.drag(list, const Offset(0, 130));
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      await tester.drag(list, const Offset(0, -130));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: button, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'cached distant navigation and return animate without scrolling a stale list',
    (tester) async {
      final repository = _CachedDiagnosticRepository();
      repository.readGate = Completer<List<ChatMessage>?>()
        ..complete([for (var i = 530; i >= 471; i--) _message('$i', i)]);
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('500', 500);
      final list = find.byType(ScrollablePositionedList);
      final initialState = tester.state(list);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      final targetBubble = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == target.id,
      );
      final entered = <double>[];
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        entered.add(tester.getTopLeft(targetBubble).dy);
      }
      final focusedState = tester.state(list);
      expect(identical(initialState, focusedState), isFalse);
      expect(entered.toSet().length, greaterThan(1));
      for (var i = 1; i < entered.length; i++) {
        expect(entered[i], greaterThan(entered[i - 1]));
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).initialScrollIndex,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(targetBubble).dy, closeTo(248, 1));
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scroll_to_bottom')));
      final recentBubble = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == '999',
      );
      final exited = <double>[];
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        exited.add(tester.getTopLeft(recentBubble).dy);
      }
      expect(identical(focusedState, tester.state(list)), isFalse);
      expect(exited.toSet().length, greaterThan(1));
      for (var i = 1; i < exited.length; i++) {
        expect(exited[i], lessThan(exited[i - 1]));
      }
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(recentBubble).dy;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getTopLeft(recentBubble).dy, settled);
      expect(find.byKey(const ValueKey('scroll_to_bottom')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  for (final action in ['drag', 'send', 'reply', 'close']) {
    testWidgets('cached viewport transition can be interrupted by $action', (
      tester,
    ) async {
      final repository = _CachedDiagnosticRepository();
      repository.readGate = Completer<List<ChatMessage>?>()
        ..complete([for (var i = 530; i >= 471; i--) _message('$i', i)]);
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      Future<void> select(ChatMessage message) async {
        bloc.add(ChatReplySelected(message));
        await tester.pump();
        await tester.pump();
        // Exercise the navigation callback while the panel itself is still
        // expanding; actual hit-testing is covered by the test above.
        tester
            .widget<ReplyComposerPreview>(
              find.byWidgetPredicate(
                (w) => w is ReplyComposerPreview && w.message.id == message.id,
              ),
            )
            .onTap!();
      }

      await select(_message('500', 500));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final transition = tester.state<HistoryViewportTransitionState>(
        find.byType(HistoryViewportTransition),
      );
      expect(transition.isAnimating, isTrue);
      switch (action) {
        case 'drag':
          await tester.drag(
            find.byType(ScrollablePositionedList),
            const Offset(0, -100),
          );
          await tester.pumpAndSettle();
          expect(transition.isAnimating, isFalse);
          expect(find.byType(MessageBubble), findsWidgets);
        case 'send':
          tester
              .widget<MessageInputBar>(find.byType(MessageInputBar))
              .onSend('interrupt transition');
          await tester.pumpAndSettle();
          expect(repository.sent, ['interrupt transition']);
          expect(
            find.byWidgetPredicate(
              (w) => w is MessageBubble && w.message.id == '999',
            ),
            findsOneWidget,
          );
        case 'reply':
          repository.readGate = Completer<List<ChatMessage>?>()
            ..complete([for (var i = 330; i >= 271; i--) _message('$i', i)]);
          await select(_message('300', 300));
          await tester.pumpAndSettle();
          final target = find.byWidgetPredicate(
            (w) => w is MessageBubble && w.message.id == '300',
          );
          expect(target, findsOneWidget);
          expect(tester.getTopLeft(target).dy, closeTo(248, 1));
          expect(repository.cachedReads, 2);
        case 'close':
          await _unmount(tester, router);
          expect(tester.takeException(), isNull);
          return;
      }
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    });
  }

  testWidgets(
    'cached transition acknowledges visible messages only after settling',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repository = _CachedDiagnosticRepository();
      final target = _message(
        '500',
        500,
      ).copyWith(isMine: false, senderId: 'peer');
      repository.refreshedMessages[target.id] = target;
      repository.readGate = Completer<List<ChatMessage>?>()
        ..complete([
          for (var i = 530; i >= 471; i--)
            i == 500 ? target : _message('$i', i),
        ]);
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.visibleReads, isEmpty);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.visibleReads, [contains('500')]);
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  for (final mediaType in [MessageType.audio, MessageType.image]) {
    for (final hasLocalUrl in [true, false]) {
      testWidgets(
        'cached $mediaType keeps ready content on remount, initial local url=$hasLocalUrl',
        (tester) async {
          final repository = _CachedDiagnosticRepository();
          final cached = [
            for (var i = 530; i >= 471; i--)
              i >= 514 && i <= 516
                  ? _message('$i', i).copyWith(
                      type: mediaType,
                      audioUrl: hasLocalUrl ? '/cached/$i.aac' : null,
                      audioStoragePath: 'chat/$i.aac',
                      mediaUrls: hasLocalUrl ? ['/cached/$i.jpg'] : const [],
                      mediaStoragePaths: ['chat/$i.jpg'],
                      audioDuration: const Duration(seconds: 5),
                    )
                  : _message('$i', i),
          ];
          repository.readGate = Completer<List<ChatMessage>?>()
            ..complete(cached);
          final router = await _mount(tester, repository);
          final bloc = BlocProvider.of<ChatBloc>(
            tester.element(find.byType(MessageBubble).first),
          );
          final target = _message('500', 500);
          bloc.add(ChatReplySelected(target));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(ReplyComposerPreview),
              matching: find.text(target.text),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          final list = find.byType(ScrollablePositionedList);
          final row = find.byKey(const ValueKey('msg_515'));
          final placeholders = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_FocusedMediaPlaceholder',
            ),
          );
          final audio = find.descendant(
            of: row,
            matching: find.byType(
              mediaType == MessageType.audio
                  ? AudioMessageContent
                  : MessageMediaGrid,
            ),
          );
          final traces = <String>[];
          for (var attempt = 0; attempt < 2; attempt++) {
            tester
                .widget<ScrollablePositionedList>(list)
                .itemScrollController!
                .jumpTo(index: 15, alignment: .3);
            await tester.pumpAndSettle();
            expect(audio, findsOneWidget);
            tester
                .widget<ScrollablePositionedList>(list)
                .itemScrollController!
                .jumpTo(index: 58, alignment: .3);
            await tester.pumpAndSettle();
            expect(row, findsNothing);
            tester
                .widget<ScrollablePositionedList>(list)
                .itemScrollController!
                .jumpTo(index: 15, alignment: .3);
            await tester.pump();
            final beforeHeight = tester.getSize(row).height;
            traces.add(
              'attempt=$attempt firstFrame placeholder=${placeholders.evaluate().length} audio=${audio.evaluate().length} height=$beforeHeight',
            );
            expect(placeholders, findsNothing);
            expect(audio, findsOneWidget);
            await tester.pump();
            traces.add(
              'attempt=$attempt secondFrame placeholder=${placeholders.evaluate().length} audio=${audio.evaluate().length} height=${tester.getSize(row).height}',
            );
            expect(audio, findsOneWidget);
            expect(tester.getSize(row).height, beforeHeight);
            await tester.pumpAndSettle();
          }
          // ignore: avoid_print
          print(
            'CACHED_AUDIO_DIAGNOSTIC ${traces.join(' | ')} reads=${repository.cachedReads} remote=${repository.windowCalls} hydrations=${repository.hydrationCounts}',
          );
          expect(repository.windowCalls, 0);
          expect(repository.hydrationCounts['515'], 1);
          expect(tester.takeException(), isNull);
          await _unmount(tester, router);
        },
      );
    }
  }

  testWidgets(
    'cached reply skips loading, starts at target and reuses local lookup',
    (tester) async {
      final repository = _CachedDiagnosticRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('500', 500);
      final cached = [for (var i = 530; i >= 471; i--) _message('$i', i)];
      final traces = <String>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        repository.readGate = Completer<List<ChatMessage>?>();
        bloc.add(ChatReplySelected(target));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ReplyComposerPreview),
            matching: find.text(target.text),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final loading = find
            .byType(CircularProgressIndicator)
            .evaluate()
            .length;
        traces.add(
          'attempt=$attempt cachedReads=${repository.cachedReads} loading=$loading remote=${repository.windowCalls}',
        );
        expect(loading, 0);
        repository.readGate!.complete(cached);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final matches = find.byWidgetPredicate(
            (w) => w is MessageBubble && w.message.id == target.id,
          );
          traces.add(
            'attempt=$attempt frame=$frame targetY=${matches.evaluate().isEmpty ? null : tester.getTopLeft(matches).dy} loading=${find.byType(CircularProgressIndicator).evaluate().length}',
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // The first painted history window already contains the target.
          expect(matches, findsOneWidget);
          // Paint motion must not change the list's final layout anchor.
          expect(tester.getTopLeft(matches).dy, inInclusiveRange(200, 249));
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .getTopLeft(
                find.byWidgetPredicate(
                  (w) => w is MessageBubble && w.message.id == target.id,
                ),
              )
              .dy,
          closeTo(248, 1),
        );
        expect(repository.windowCalls, 0);
        tester
            .widget<MessageInputBar>(find.byType(MessageInputBar))
            .onSend('return live');
        await tester.pumpAndSettle();
      }
      // ignore: avoid_print
      print('CACHED_REPLY_DIAGNOSTIC ${traces.join(' | ')}');
      expect(repository.cachedReads, 1);
      // A memory hit must retain SQLite pagination rather than switching to RPCs.
      expect(repository.olderWindowCalls, 0);
      expect(repository.newerWindowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets('returning live cancels an outstanding local reply lookup', (
    tester,
  ) async {
    final repository = _CachedDiagnosticRepository();
    final router = await _mount(tester, repository);
    final bloc = BlocProvider.of<ChatBloc>(
      tester.element(find.byType(MessageBubble).first),
    );
    final target = _message('500', 500);
    repository.readGate = Completer<List<ChatMessage>?>();
    bloc.add(ChatReplySelected(target));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ReplyComposerPreview),
        matching: find.text(target.text),
      ),
    );
    await tester.pump();
    expect(repository.cachedReads, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester
        .widget<MessageInputBar>(find.byType(MessageInputBar))
        .onSend('cancel lookup');
    await tester.pumpAndSettle();
    repository.readGate!.complete(null);
    await tester.pumpAndSettle();
    expect(repository.windowCalls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .maintainVisiblePosition,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester, router);
  });

  testWidgets(
    'reused SQLite reply retains local pagination and deletion invalidation',
    (tester) async {
      final repository = _CachedDiagnosticRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('500', 500);
      final cached = [for (var i = 530; i >= 471; i--) _message('$i', i)];
      repository.readGate = Completer<List<ChatMessage>?>()..complete(cached);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(
          find.descendant(
            of: find.byType(ReplyComposerPreview),
            matching: find.text(target.text),
          ),
        );
        await tester.pumpAndSettle();
        if (attempt == 0) {
          tester
              .widget<MessageInputBar>(find.byType(MessageInputBar))
              .onSend('return live');
          await tester.pumpAndSettle();
          bloc.add(ChatReplySelected(target));
          await tester.pumpAndSettle();
        }
      }
      expect(repository.cachedReads, 1);
      final list = find.byType(ScrollablePositionedList);
      for (var i = 0; i < 7; i++) {
        await tester.drag(list, const Offset(0, 350));
        await tester.pumpAndSettle();
      }
      expect(repository.olderCalls, greaterThan(0));
      for (var i = 0; i < 7; i++) {
        await tester.drag(list, const Offset(0, -350));
        await tester.pumpAndSettle();
      }
      expect(repository.olderWindowCalls, 0);
      expect(repository.newerWindowCalls, 0);
      expect(repository.windowCalls, 0);
      repository.events.add(ChatHistoryChange.deleted(target.id));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message.id == target.id,
        ),
        findsNothing,
      );
      // The next jump must consult SQLite again after invalidation, and a stale
      // delayed response must not resurrect a message deleted during that read.
      tester
          .widget<MessageInputBar>(find.byType(MessageInputBar))
          .onSend('return again');
      await tester.pumpAndSettle();
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      repository.readGate = Completer<List<ChatMessage>?>();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      expect(repository.cachedReads, 2);
      repository.events.add(ChatHistoryChange.deleted(target.id));
      await tester.pump();
      repository.readGate!.complete(cached);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message.id == target.id,
        ),
        findsNothing,
      );
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'crossing into the head cancels a stale page lock before reentering history',
    (tester) async {
      final repository = _CachedDiagnosticRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('920', 920);
      repository.readGate = Completer<List<ChatMessage>?>()
        ..complete([for (var i = 960; i >= 901; i--) _message('$i', i)]);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pumpAndSettle();
      final gate = repository.newerHistoryGate = Completer<void>();
      final list = find.byType(ScrollablePositionedList);
      final gesture = await tester.startGesture(tester.getCenter(list));
      for (
        var i = 0;
        i < 100 &&
            tester
                .widget<ScrollablePositionedList>(list)
                .maintainVisiblePosition;
        i++
      ) {
        await gesture.moveBy(const Offset(0, -35));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isFalse,
      );
      // A page may still be waiting while the viewport fits the recent head.
      expect(repository.newerHistoryCalls, 1);
      for (var i = 0; i < 180; i++) {
        await gesture.moveBy(const Offset(0, 35));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(repository.olderCalls, greaterThan(1));
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isTrue,
      );
      await gesture.up();
      gate.complete();
      await tester.pumpAndSettle();
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'mouse wheel can enter and leave the bounded history without a drag',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final list = find.byType(ScrollablePositionedList);
      for (var i = 0; i < 25; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: const Offset(0, -150),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(repository.olderCalls, greaterThan(0));
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isTrue,
      );
      for (var i = 0; i < 30; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: const Offset(0, 150),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isFalse,
      );
      expect(repository.windowCalls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  for (final variant in [
    'single-day',
    'multiple-days',
    'multiple-days-reactions',
  ]) {
    testWidgets(
      'continuous bidirectional scrolling has no blank frames or head/window loop $variant',
      (tester) async {
        final repository = variant == 'single-day'
            ? _BoundedRepository()
            : _DailyDiagnosticRepository(
                withReactions: variant.endsWith('reactions'),
              );
        final router = await _mount(tester, repository);
        final list = find.byType(ScrollablePositionedList);
        final gesture = await tester.startGesture(tester.getCenter(list));
        Map<String, ({State state, double y})> snapshot() {
          final result = <String, ({State state, double y})>{};
          for (final element in find.byType(MessageBubble).evaluate()) {
            final finder = find.byWidget(element.widget);
            final rect = tester.getRect(finder);
            if (rect.top < 110 || rect.bottom > 470) continue;
            result[(element.widget as MessageBubble).message.id] = (
              state: tester.state(finder),
              y: rect.top,
            );
          }
          return result;
        }

        var previous = snapshot();
        final resets = <String>[];
        final reversals = <String>[];
        final discontinuities = <String>[];
        final transitions = <String>[];
        final blankFrames = <String>[];
        var wasFocused = false;
        for (var frame = 0; frame < 800; frame++) {
          final delta = frame < 400 ? 35.0 : -35.0;
          await gesture.moveBy(Offset(0, delta));
          await tester.pump(const Duration(milliseconds: 16));
          final current = snapshot();
          var coveredPixels = 0.0;
          for (final element in find.byType(MessageBubble).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            coveredPixels +=
                ((rect.bottom < 470 ? rect.bottom : 470) -
                        (rect.top > 110 ? rect.top : 110))
                    .clamp(0.0, 360.0);
          }
          if (coveredPixels == 0) blankFrames.add('$frame');
          final focused = tester
              .widget<ScrollablePositionedList>(list)
              .maintainVisiblePosition;
          if (focused != wasFocused) {
            transitions.add(
              '$frame:${focused ? 'window' : 'head'}:delta=$delta:ids=${current.keys.join(',')}',
            );
            wasFocused = focused;
          }
          final atBottom = tester
              .widget<ScrollablePositionedList>(list)
              .itemPositionsNotifier!
              .itemPositions
              .value
              .any((p) => p.index == 0 && p.itemLeadingEdge >= 0);
          for (final entry in current.entries) {
            final old = previous[entry.key];
            if (old == null) continue;
            if (!identical(old.state, entry.value.state)) {
              resets.add('$frame:${entry.key}');
            }
            final dy = entry.value.y - old.y;
            if (dy * delta < -2) reversals.add('$frame:${entry.key}:dy=$dy');
            if (frame > 3 &&
                (frame < 400 || frame > 404) &&
                !atBottom &&
                (dy - delta).abs() > 2) {
              discontinuities.add('$frame:${entry.key}:dy=$dy');
            }
          }
          previous = current;
          expect(tester.takeException(), isNull);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        // ignore: avoid_print
        print(
          'CONTINUOUS_TEXT_DIAGNOSTIC variant=$variant resets=${resets.length} ${resets.take(12).toList()} reversals=${reversals.length} ${reversals.take(12).toList()} discontinuities=${discontinuities.length} ${discontinuities.take(12).toList()} blankFrames=$blankFrames older=${repository.olderCalls} frontiers=${repository.diagnosticOlderFrontiers} transitions=$transitions',
        );
        expect(resets, isEmpty);
        expect(reversals, isEmpty);
        expect(discontinuities, isEmpty);
        expect(blankFrames, isEmpty);
        expect(
          repository.diagnosticOlderFrontiers.where((id) => id == '940').length,
          1,
        );
        expect(transitions.where((line) => line.contains(':head:')).length, 1);
        await _unmount(tester, router);
      },
    );
  }

  // Real ChatPage regression coverage for sending while the IME is resizing.
  for (final index in [0, 20, 45]) {
    for (final delayFrames in [0, 1, 2, 5]) {
      testWidgets(
        'ordinary send with keyboard keeps timeline visible index=$index delay=$delayFrames',
        (tester) async {
          addTearDown(tester.view.resetViewInsets);
          final repository = _BoundedRepository();
          final router = await _mount(tester, repository);
          final list = find.byType(ScrollablePositionedList);
          tester
              .widget<ScrollablePositionedList>(list)
              .itemScrollController!
              .jumpTo(index: index, alignment: .2);
          await tester.pumpAndSettle();
          final bloc = BlocProvider.of<ChatBloc>(
            tester.element(find.byType(MessageBubble).first),
          );
          tester
              .widget<MessageInputBar>(find.byType(MessageInputBar))
              .onSend('diagnostic send');
          for (var i = 0; i < delayFrames; i++) {
            tester.view.viewInsets = FakeViewPadding(bottom: i * 40);
            await tester.pump(const Duration(milliseconds: 16));
          }
          final pending = _message(
            '1000',
            1000,
          ).copyWith(status: MessageStatus.sending);
          bloc.add(
            ChatMessagesReceived([pending, ...repository.messages.take(59)]),
          );
          for (var i = 0; i < 20; i++) {
            tester.view.viewInsets = FakeViewPadding(
              bottom: (i * 20).clamp(0, 300).toDouble(),
            );
            await tester.pump(const Duration(milliseconds: 16));
            if (i == 5) {
              bloc.add(
                ChatMessagesReceived([
                  pending.copyWith(status: MessageStatus.sent),
                  ...repository.messages.take(59),
                ]),
              );
            }
          }
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          final widget = tester.widget<ScrollablePositionedList>(list);
          final visible = widget.itemPositionsNotifier!.itemPositions.value
              .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
              .length;
          final listFades = tester
              .widgetList<FadeTransition>(
                find.descendant(
                  of: list,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is FadeTransition &&
                        w.child is NotificationListener<ScrollNotification>,
                  ),
                ),
              )
              .map((w) => w.opacity.value)
              .toList();
          expect(visible, greaterThan(0));
          expect(
            widget.itemPositionsNotifier!.itemPositions.value.any(
              (p) =>
                  p.index == 0 &&
                  p.itemTrailingEdge > 0 &&
                  p.itemLeadingEdge < 1,
            ),
            isTrue,
          );
          expect(listFades.any((opacity) => opacity > .99), isTrue);
          expect(repository.sent, ['diagnostic send']);
          expect(tester.takeException(), isNull);
          await _unmount(tester, router);
        },
      );
    }
  }
  testWidgets(
    'ordinary history entry and return to the live head keep the active viewport',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final list = find.byType(ScrollablePositionedList);
      tester
          .widget<ScrollablePositionedList>(list)
          .itemScrollController!
          .jumpTo(index: 54, alignment: .25);
      await tester.pumpAndSettle();
      final gate = repository.olderHistoryGate = Completer<void>();
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(repository.olderCalls, 1);
      final row = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == '943',
      );
      final state = tester.state(row);
      final position = Scrollable.of(tester.element(row)).position;
      final y = tester.getTopLeft(row).dy;
      gate.complete();
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isTrue,
      );
      expect(identical(state, tester.state(row)), isTrue);
      expect(
        identical(position, Scrollable.of(tester.element(row)).position),
        isTrue,
      );
      expect(position.activity, isA<DragScrollActivity>());
      expect(tester.getTopLeft(row).dy, closeTo(y, 1));
      await gesture.up();
      await tester.pumpAndSettle();
      // Keep the history while any old-only row is exposed. Only switch after
      // the entire viewport fits the head, without replacing the Scrollable.
      final back = await tester.startGesture(tester.getCenter(list));
      await back.moveBy(const Offset(0, -30));
      await tester.pump();
      await back.moveBy(const Offset(0, -60));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isTrue,
      );
      for (
        var i = 0;
        i < 16 &&
            tester
                .widget<ScrollablePositionedList>(list)
                .maintainVisiblePosition;
        i++
      ) {
        await back.moveBy(const Offset(0, -30));
        await tester.pump();
      }
      expect(
        tester.widget<ScrollablePositionedList>(list).maintainVisiblePosition,
        isFalse,
      );
      expect(
        identical(position, Scrollable.of(tester.element(row)).position),
        isTrue,
      );
      expect(position.activity, isA<DragScrollActivity>());
      expect(identical(state, tester.state(row)), isTrue);
      await back.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'uncached newer page arriving under a finger retains real message state and drag',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('remote-target', -1000);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      repository.window.complete([
        for (var i = -970; i >= -1029; i--)
          i == -1000 ? target : _message('remote-$i', i),
      ]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final list = find.byType(ScrollablePositionedList);
      tester
          .widget<ScrollablePositionedList>(list)
          .itemScrollController!
          .jumpTo(index: 7, alignment: .3);
      await tester.pumpAndSettle();
      final gate = repository.newerWindowGate = Completer<void>();
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(repository.newerWindowCalls, 1);
      final visibleBubble = find.byType(MessageBubble).evaluate().firstWhere((
        element,
      ) {
        final y = tester.getTopLeft(find.byWidget(element.widget)).dy;
        return y > 130 && y < 350;
      });
      final id = (visibleBubble.widget as MessageBubble).message.id;
      final row = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == id,
      );
      final state = tester.state(row);
      final position = Scrollable.of(tester.element(row)).position;
      final y = tester.getTopLeft(row).dy;
      expect(position.activity, isA<DragScrollActivity>());
      gate.complete();
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(identical(state, tester.state(row)), isTrue);
        expect(
          identical(position, Scrollable.of(tester.element(row)).position),
          isTrue,
        );
        expect(position.activity, isA<DragScrollActivity>());
        expect(tester.getTopLeft(row).dy, closeTo(y, 1));
      }
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(tester.getTopLeft(row).dy, closeTo(y - 40, 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(repository.windowCalls, 1);
      expect(repository.olderCalls, 0);
      expect(bloc.state.messages, hasLength(60));
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'uncached reply paginates both ways without using local-history cursors',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('remote-target', -1000);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      repository.window.complete([
        for (var i = -970; i >= -1029; i--)
          i == -1000 ? target : _message('remote-$i', i),
      ]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final list = find.byType(ScrollablePositionedList);
      for (var i = 0; i < 40; i++) {
        await tester.drag(list, const Offset(0, 650));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ScrollablePositionedList>(list).itemCount,
          lessThanOrEqualTo(245),
        );
        expect(tester.takeException(), isNull);
      }
      expect(repository.olderWindowCalls, greaterThan(4));
      for (var i = 0; i < 40; i++) {
        await tester.drag(list, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ScrollablePositionedList>(list).itemCount,
          lessThanOrEqualTo(245),
        );
        expect(tester.takeException(), isNull);
      }
      expect(repository.newerWindowCalls, greaterThan(0));
      expect(repository.olderCalls, 0);
      expect(bloc.state.messages, hasLength(60));
      expect(repository.windowCalls, 1);
      await _unmount(tester, router);
    },
  );
  testWidgets(
    'bounded feed scrolls through local history and returns to live head',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final list = find.byType(ScrollablePositionedList);
      expect(bloc.state.messages, hasLength(60));
      for (var page = 0; page < 40; page++) {
        await tester.drag(list, const Offset(0, 650));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ScrollablePositionedList>(list).itemCount,
          lessThanOrEqualTo(245),
        );
        expect(tester.takeException(), isNull);
      }
      expect(repository.olderCalls, greaterThan(4));
      expect(bloc.state.messages, hasLength(60));
      expect(repository.windowCalls, 0);
      // Sending while in ordinary old history uses the live feed, just as a send
      // from a reply window does. It must not replace the screen with empty rows.
      tester
          .widget<MessageInputBar>(find.byType(MessageInputBar))
          .onSend('new outgoing');
      await tester.pumpAndSettle();
      expect(find.byType(MessageBubble), findsWidgets);
      expect(repository.sent, ['new outgoing']);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets('a burst cannot evict the visible row from the bounded head', (
    tester,
  ) async {
    final repository = _BoundedRepository();
    final router = await _mount(tester, repository);
    final bloc = BlocProvider.of<ChatBloc>(
      tester.element(find.byType(MessageBubble).first),
    );
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();
    final visible = find.byType(MessageBubble).evaluate().where((e) {
      final y = tester.getTopLeft(find.byWidget(e.widget)).dy;
      return y > 150 && y < 400;
    }).first;
    final target = (visible.widget as MessageBubble).message.id;
    final bubble = find.byWidgetPredicate(
      (w) => w is MessageBubble && w.message.id == target,
    );
    final top = tester.getTopLeft(bubble).dy;
    bloc.add(
      ChatMessagesReceived([
        for (var i = 1099; i >= 1040; i--)
          _message('$i', i).copyWith(senderId: 'peer', isMine: false),
      ]),
    );
    await tester.pumpAndSettle();
    expect(bubble, findsOneWidget);
    expect(tester.getTopLeft(bubble).dy, closeTo(top, 1));
    expect(find.byKey(const ValueKey('scroll_to_bottom')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scroll_to_bottom')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == '1099',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester, router);
  });

  testWidgets(
    'bounded repository keeps uncached reply navigation on original path',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('far', 2000);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      expect(repository.windowCalls, 1);
      repository.window.complete([
        _message('after', 2001),
        target,
        _message('before', 1999),
      ]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.olderCalls, 0);
      final bubble = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == target.id,
      );
      expect(bubble, findsOneWidget);
      final top = tester.getTopLeft(bubble).dy;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.windowCalls, 1);
      expect(tester.getTopLeft(bubble).dy, closeTo(top, 1));
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );

  testWidgets(
    'uncached reply keeps position on arrival, removes deletes, and can send',
    (tester) async {
      final repository = _BoundedRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('remote-target', -1000);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.text(target.text),
        ),
      );
      await tester.pump();
      repository.window.complete([
        for (var i = -970; i >= -1029; i--)
          i == -1000 ? target : _message('remote-$i', i),
      ]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final bubble = find.byWidgetPredicate(
        (w) => w is MessageBubble && w.message.id == target.id,
      );
      final top = tester.getTopLeft(bubble).dy;
      bloc.add(
        ChatMessagesReceived([
          _message('1000', 1000).copyWith(senderId: 'peer', isMine: false),
          ...repository.messages.take(59),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(bubble).dy, closeTo(top, 1));
      expect(find.byKey(const ValueKey('scroll_to_bottom')), findsOneWidget);
      expect(repository.olderCalls, 0);
      repository.events.add(ChatHistoryChange.deleted(target.id));
      await tester.pumpAndSettle();
      expect(bubble, findsNothing);
      tester
          .widget<MessageInputBar>(find.byType(MessageInputBar))
          .onSend('from reply window');
      await tester.pumpAndSettle();
      expect(repository.sent, ['from reply window']);
      expect(
        find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message.id == '1000',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    },
  );
  for (final deleted in [false, true]) {
    for (final size in [const Size(390, 780), const Size(780, 390)]) {
      testWidgets(
        'bottom chat action uses glass: deleted=$deleted size=$size',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final blocks = MockBlocklistRepository();
          if (!deleted) {
            await blocks.blockUser(
              BlockedUser(
                id: 'peer',
                username: 'peer',
                displayName: 'Peer',
                blockedAt: DateTime(2026),
              ),
            );
          }
          final chats = _ChatsRepository();
          if (deleted) chats.deletion = Completer<void>();
          final router = await _mount(
            tester,
            _ChatRepository(),
            deleted: deleted,
            blocks: blocks,
            chats: chats,
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ChatPage)),
          )!;
          final label = deleted
              ? l10n.chatsDeleteAccountChat
              : l10n.unblockUser.toLowerCase();
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byType(ChatGlassSurface),
          );
          expect(button, findsOneWidget);
          expect(tester.widget<ChatGlassSurface>(button).lightStyle, isFalse);
          expect(tester.getSize(button), Size(size.width - 32, 50));
          expect(tester.getBottomLeft(button).dy, size.height - 8);
          expect(
            find.descendant(of: button, matching: find.byType(BackdropFilter)),
            findsOneWidget,
          );
          expect(find.byType(TextField), findsNothing);
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
          await tester.pumpAndSettle();
          expect(find.text(label), findsOneWidget);
          expect(chats.deletedIds, isEmpty);
          if (!deleted) {
            expect(await blocks.watchBlockedUserIds().first, contains('peer'));
          }
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          if (deleted) {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(chats.deletedIds, {'chat'});
            final pendingButton = find.ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(ChatGlassSurface),
            );
            expect(pendingButton, findsOneWidget);
            final ink = find.descendant(
              of: pendingButton,
              matching: find.byType(InkWell),
            );
            expect(tester.widget<InkWell>(ink).onTap, isNull);
            expect(tester.getSize(pendingButton), Size(size.width - 32, 50));
            chats.deletion!.complete();
            await tester.pumpAndSettle();
            expect(find.text('chat-list'), findsOneWidget);
          } else {
            await tester.pumpAndSettle();
            expect(await blocks.watchBlockedUserIds().first, isEmpty);
            expect(find.byType(TextField), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await _unmount(tester, router);
        },
      );
    }
  }

  for (final distant in [false, true]) {
    for (final entity in [
      '@alice',
      '+79991234567',
      'https://links.yapchat.ru/alice',
    ]) {
      testWidgets(
        'actual chat opens text profile: distant=$distant entity=$entity',
        (tester) async {
          final repository = _ChatRepository();
          final friends = _TextFriends();
          final profiles = _TextProfiles();
          final target = _message(
            distant ? 'far' : '80',
            distant ? 1000 : 80,
          ).copyWith(text: entity);
          if (!distant) {
            repository.messages[0] = target;
          }
          final router = await _mount(
            tester,
            repository,
            friends: friends,
            profiles: profiles,
          );
          if (distant) {
            final bloc = BlocProvider.of<ChatBloc>(
              tester.element(find.byType(MessageBubble).first),
            );
            bloc.add(ChatReplySelected(target));
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(ReplyComposerPreview),
                matching: find.text(entity),
              ),
            );
            await tester.pump();
            repository.window.complete([
              _message('after', 1001),
              target,
              _message('before', 999),
            ]);
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 1));
          }
          expect(friends.calls, 0);
          expect(profiles.calls, 0);
          final bubble = find.byWidgetPredicate(
            (w) => w is MessageBubble && w.message.id == target.id,
          );
          final rich = find
              .descendant(
                of: find.descendant(
                  of: bubble,
                  matching: find.byType(MessageTextContent),
                ),
                matching: find.byType(RichText),
              )
              .first;
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          final box = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: entity.length),
              )
              .first
              .toRect();
          await tester.tapAt(paragraph.localToGlobal(box.center));
          await tester.pumpAndSettle();
          expect(find.text('viewed-profile-found-chat'), findsOneWidget);
          expect(friends.calls, entity.startsWith('https:') ? 0 : 1);
          expect(profiles.calls, entity.startsWith('https:') ? 1 : 0);
          expect(repository.windowCalls, distant ? 1 : 0);
          expect(tester.takeException(), isNull);
          await _unmount(tester, router);
        },
      );
    }
  }
  for (final distant in [false, true]) {
    testWidgets('composer uses real chat navigation: distant=$distant', (
      tester,
    ) async {
      final repository = _ChatRepository();
      final router = await _mount(tester, repository);
      final target = distant ? _message('far', 1000) : repository.messages[40];
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      final preview = find.byType(ReplyComposerPreview);
      await tester.tap(
        find.descendant(of: preview, matching: find.text(target.text)),
      );
      await tester.pump();
      if (distant) {
        // Fast repeated taps share the existing window-loading guard.
        await tester.tap(
          find.descendant(of: preview, matching: find.text(target.text)),
        );
        await tester.pump();
        expect(repository.windowCalls, 1);
        repository.window.complete([
          _message('after', 1001),
          target,
          _message('before', 999),
        ]);
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.windowCalls, distant ? 1 : 0);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is MessageBubble && widget.message.id == target.id,
        ),
        findsOneWidget,
      );
      expect(bloc.state.replyToMessage, target);
      // The selected quote remains mounted; navigation never submits/clears it.
      expect(find.byType(ReplyComposerPreview), findsOneWidget);
      if (distant) {
        await tester.tap(
          find.descendant(of: preview, matching: find.text(target.text)),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(repository.windowCalls, 1);
      }
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('unavailable composer target keeps the reply: fails=$fails', (
      tester,
    ) async {
      final repository = _ChatRepository();
      final router = await _mount(tester, repository);
      final bloc = BlocProvider.of<ChatBloc>(
        tester.element(find.byType(MessageBubble).first),
      );
      final target = _message('unavailable', 1000);
      bloc.add(ChatReplySelected(target));
      await tester.pumpAndSettle();
      final preview = find.byType(ReplyComposerPreview);
      final l10n = AppLocalizations.of(tester.element(preview))!;
      await tester.tap(
        find.descendant(of: preview, matching: find.text(target.text)),
      );
      await tester.pump();
      if (fails) {
        repository.window.completeError(StateError('offline'));
      } else {
        repository.window.complete([]);
      }
      await tester.pumpAndSettle();
      expect(
        find.text(fails ? l10n.messageJumpFailed : l10n.messageNotAvailable),
        findsOneWidget,
      );
      expect(bloc.state.replyToMessage, target);
      expect(repository.windowCalls, 1);
      expect(find.byType(MessageBubble), findsWidgets);
      expect(tester.takeException(), isNull);
      await _unmount(tester, router);
    });
  }
}

// SDK/cache stream cancellations can complete outside the widget fake-async
// zone. Drain both zones; pumpAndSettle alone only sees scheduled UI frames.
Future<void> _flushSubmissionFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pumpAndSettle();
  }
}

Future<_Router> _mount(
  WidgetTester tester,
  _ChatRepository repository, {
  _TextFriends? friends,
  _TextProfiles? profiles,
  bool deleted = false,
  MockBlocklistRepository? blocks,
  _ChatsRepository? chats,
  Chat? initialChat,
  ILocalMediaRepository? media,
}) async {
  final blocklist = blocks ?? MockBlocklistRepository();
  final router = _Router(
    withProfiles: friends != null,
    deleted: deleted,
    initialChat: initialChat,
  );
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        if (friends != null)
          RepositoryProvider<IFriendsRepository>.value(value: friends),
        if (profiles != null)
          RepositoryProvider<IProfileRepository>.value(value: profiles),
        RepositoryProvider<IChatRepository>.value(value: repository),
        RepositoryProvider<IChatsRepository>.value(
          value: chats ?? _ChatsRepository(),
        ),
        RepositoryProvider<IBlocklistRepository>.value(value: blocklist),
        RepositoryProvider<IAudioPlayerRepository>.value(value: _Player()),
        RepositoryProvider<IAudioRecorderRepository>.value(value: _Recorder()),
        RepositoryProvider<ILocalMediaRepository>.value(
          value: media ?? _Media(),
        ),
        RepositoryProvider<AppConfig>.value(value: _Config()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: _Auth()),
          BlocProvider(create: (_) => BlocklistCubit(repository: blocklist)),
          BlocProvider(
            create: (_) => PresenceCubit(repository: MockPresenceRepository()),
          ),
          BlocProvider(
            create: (_) => NotificationsCubit(
              repository: const MockPushNotificationsRepository(),
            ),
          ),
        ],
        child: MaterialApp.router(
          builder: (_, child) => KeyboardResumeScope(child: child!),
          routerConfig: router.config(
            navigatorObservers: () => [AutoRouteObserver()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (deleted) {
    unawaited(router.push(const NamedRoute('chat')));
    await tester.pumpAndSettle();
  }
  return router;
}

Future<void> _unmount(WidgetTester tester, _Router router) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  router.dispose();
}

Future<bool> _requestKeyboardResume(WidgetTester tester) {
  final result = Completer<bool>();
  const codec = StandardMethodCodec();
  tester.binding.channelBuffers.push(
    'com.yapchat.app/keyboard_resume',
    codec.encodeMethodCall(
      MethodCall('restoreFocusedInput', {
        'deadlineMs': DateTime.now().millisecondsSinceEpoch + 900,
      }),
    ),
    (reply) => result.complete(codec.decodeEnvelope(reply!) == true),
  );
  return result.future;
}

class _Router extends RootStackRouter {
  _Router({this.withProfiles = false, this.deleted = false, this.initialChat});
  final Chat? initialChat;
  final bool withProfiles;
  final bool deleted;
  @override
  List<AutoRoute> get routes => withProfiles
      ? [
          NamedRouteDef(
            name: AuthGateRoute.name,
            path: '/',
            initial: true,
            builder: (_, _) => const AutoRouter(),
            children: [
              ..._chatRoutes,
              NamedRouteDef(
                name: ViewedProfileRoute.name,
                path: 'profile',
                builder: (_, data) {
                  final args = data.argsAs<ViewedProfileRouteArgs>();
                  return Scaffold(
                    body: Text(
                      'viewed-profile-${args.userId}-${args.originChatId}',
                    ),
                  );
                },
              ),
            ],
          ),
        ]
      : _chatRoutes;

  List<AutoRoute> get _chatRoutes => [
    if (deleted)
      NamedRouteDef(
        name: 'chat-list',
        path: '/',
        initial: true,
        builder: (_, _) => const Scaffold(body: Text('chat-list')),
      ),
    NamedRouteDef(
      name: 'chat',
      path: deleted ? '/chat' : (withProfiles ? '' : '/'),
      initial: !deleted,
      builder: (_, _) => ChatPage(
        chat:
            initialChat ??
            Chat(
              id: 'chat',
              peerId: 'peer',
              userName: 'Peer',
              lastMessage: '',
              lastMessageTime: DateTime(2026),
              unreadCount: 0,
              isOnline: false,
              isLastMessageFromMe: false,
              peerIsDeleted: deleted,
            ),
      ),
    ),
  ];
}

class _TextFriends implements IFriendsRepository {
  int calls = 0;
  static const candidate = FriendCandidate(
    id: 'found',
    username: 'alice',
    displayName: 'Alice',
    relationship: FriendRelationship.none,
  );
  @override
  Future<List<FriendCandidate>> searchUsers(String query) async {
    calls++;
    expect(query, '@alice');
    return [candidate];
  }

  @override
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phone) async {
    calls++;
    expect(phone, '+79991234567');
    return ContactMatchSnapshot(matches: {phone: candidate});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextProfiles implements IProfileRepository {
  int calls = 0;
  @override
  Future<String?> resolveSharedProfileUsername(String username) async {
    calls++;
    expect(username, 'alice');
    return 'found';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatMessage _message(String id, int minute) => ChatMessage(
  id: id,
  chatId: 'chat',
  senderId: 'me',
  text: 'message $id',
  timestamp: DateTime(2026).add(Duration(minutes: minute)),
  isMine: true,
  status: MessageStatus.read,
);

class _ChatRepository implements IChatRepository {
  final messages = [for (var i = 80; i >= 0; i--) _message('$i', i)];
  final window = Completer<List<ChatMessage>>();
  int windowCalls = 0;
  final List<Set<String>> visibleReads = [];
  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) =>
      Stream.value(messages);
  @override
  Stream<ChatHistoryChange> watchHistoryChanges(String chatId) =>
      const Stream.empty();
  @override
  Future<void> reconcileVisibleMessages(String chatId, Set<String> ids) async {}
  @override
  Future<void> markVisibleMessagesRead(String chatId, Set<String> ids) async {
    visibleReads.add(Set.of(ids));
  }

  @override
  Future<bool> loadMoreMessages(String chatId) async => false;
  @override
  Future<List<ChatMessage>> loadMessageWindow(String chatId, String messageId) {
    windowCalls++;
    return window.future;
  }

  @override
  Future<ChatMessage> hydrateWindowMedia(ChatMessage message) async => message;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoundedRepository extends _ChatRepository
    implements IBoundedChatHistory {
  _BoundedRepository() {
    messages
      ..clear()
      ..addAll([for (var i = 999; i >= 940; i--) _message('$i', i)]);
    addTearDown(events.close);
  }
  int olderCalls = 0;
  final List<String> diagnosticOlderFrontiers = [];
  int olderWindowCalls = 0;
  int newerWindowCalls = 0;
  Completer<void>? newerWindowGate;
  Completer<void>? olderHistoryGate;
  Completer<void>? newerHistoryGate;
  int newerHistoryCalls = 0;
  final List<String> sent = [];
  final events = StreamController<ChatHistoryChange>.broadcast();
  @override
  Future<List<ChatMessage>> loadWindowOlder(
    String chatId,
    ChatMessage oldest,
  ) async {
    olderWindowCalls++;
    final cursor = oldest.timestamp.difference(DateTime(2026)).inMinutes;
    return [
      for (var i = cursor - 1; i >= cursor - 60; i--) _message('remote-$i', i),
    ];
  }

  @override
  Future<List<ChatMessage>> loadWindowNewer(
    String chatId,
    ChatMessage newest,
  ) async {
    newerWindowCalls++;
    final gate = newerWindowGate;
    if (gate != null) await gate.future;
    final cursor = newest.timestamp.difference(DateTime(2026)).inMinutes;
    return [
      for (var i = cursor + 60; i > cursor; i--) _message('remote-$i', i),
    ];
  }

  @override
  Stream<ChatHistoryChange> watchHistoryChanges(String chatId) => events.stream;
  @override
  Future<List<ChatMessage>?> readCachedHistoryWindow(
    String chatId,
    String messageId, {
    bool allowUnverified = false,
  }) async => null;
  @override
  Future<List<ChatMessage>> loadHistoryOlder(
    String chatId,
    ChatMessage oldest,
  ) async {
    olderCalls++;
    diagnosticOlderFrontiers.add(oldest.id);
    final gate = olderHistoryGate;
    if (gate != null) await gate.future;
    final cursor = int.parse(oldest.id);
    return [
      for (var i = cursor - 1; i >= 0 && i >= cursor - 60; i--)
        _message('$i', i),
    ];
  }

  @override
  Future<List<ChatMessage>> loadHistoryNewer(
    String chatId,
    ChatMessage newest,
  ) async {
    newerHistoryCalls++;
    final gate = newerHistoryGate;
    if (gate != null) await gate.future;
    final cursor = int.parse(newest.id);
    return [
      for (var i = (cursor + 60).clamp(0, 999); i > cursor; i--)
        _message('$i', i),
    ];
  }

  @override
  Future<List<ChatMessage>> refreshHistoryMessages(
    String chatId,
    Set<String> ids,
  ) async => [for (final id in ids) _message(id, int.parse(id))];
  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) async {
    sent.add(text);
  }
}

class _CachedDiagnosticRepository extends _BoundedRepository {
  int cachedReads = 0;
  final Map<String, ChatMessage> refreshedMessages = {};
  final Map<String, int> hydrationCounts = {};
  Completer<List<ChatMessage>?>? readGate;
  @override
  Future<List<ChatMessage>> refreshHistoryMessages(
    String chatId,
    Set<String> ids,
  ) async => [
    for (final message in await super.refreshHistoryMessages(chatId, ids))
      refreshedMessages[message.id] ?? message,
  ];
  @override
  Future<ChatMessage> hydrateWindowMedia(ChatMessage message) async {
    hydrationCounts.update(message.id, (n) => n + 1, ifAbsent: () => 1);
    return switch (message.type) {
      MessageType.audio => message.copyWith(
        audioUrl: '/cached/${message.id}.aac',
      ),
      MessageType.image => message.copyWith(
        mediaUrls: ['/cached/${message.id}.jpg'],
      ),
      _ => message,
    };
  }

  @override
  Future<List<ChatMessage>?> readCachedHistoryWindow(
    String chatId,
    String messageId, {
    bool allowUnverified = false,
  }) {
    cachedReads++;
    return readGate!.future;
  }
}

class _DailyDiagnosticRepository extends _BoundedRepository {
  _DailyDiagnosticRepository({required this.withReactions}) {
    final changed = messages.map(_adjust).toList();
    messages
      ..clear()
      ..addAll(changed);
  }
  final bool withReactions;
  ChatMessage _adjust(ChatMessage message) {
    final minute = int.parse(message.id);
    return message.copyWith(
      timestamp: DateTime(2026).add(Duration(hours: minute * 2)),
      text: List.filled(1 + minute % 4, 'message ${message.id}').join('\n'),
      reactionState: withReactions && minute % 3 == 0
          ? const MessageReactionState(
              version: 1,
              reactions: [
                MessageReaction(userId: 'me', code: ReactionCode.heart),
              ],
            )
          : const MessageReactionState(),
    );
  }

  @override
  Future<List<ChatMessage>> loadHistoryOlder(
    String chatId,
    ChatMessage oldest,
  ) async =>
      (await super.loadHistoryOlder(chatId, oldest)).map(_adjust).toList();
  @override
  Future<List<ChatMessage>> loadHistoryNewer(
    String chatId,
    ChatMessage newest,
  ) async =>
      (await super.loadHistoryNewer(chatId, newest)).map(_adjust).toList();
  @override
  Future<List<ChatMessage>> refreshHistoryMessages(
    String chatId,
    Set<String> ids,
  ) async =>
      (await super.refreshHistoryMessages(chatId, ids)).map(_adjust).toList();
}

Chat _admittedChat() => Chat(
  id: 'admitted',
  peerId: 'peer',
  userName: 'Peer',
  lastMessage: '',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

class _AdmissionChats extends _ChatsRepository implements IChatsPeerRepository {
  _AdmissionChats() {
    addTearDown(peers.close);
  }
  final peers = StreamController<Chat?>.broadcast();
  int created = 0;
  Object? error;
  Completer<Chat>? gate;
  @override
  Stream<Chat?> watchChatByPeerId(String peerId) => peers.stream;
  @override
  Future<Chat> ensureDirectChat(String peerId) async {
    created++;
    if (error case final failure?) throw failure;
    return gate == null ? _admittedChat() : gate!.future;
  }
}

class _AdmissionMessages extends _ChatRepository {
  _AdmissionMessages() {
    messages.clear();
  }
  final sent = <String>[];
  final images = <List<String>>[];
  final audio = <RecordedAudio>[];
  @override
  Future<void> sendAudio(
    String chatId,
    String path,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) async {
    expect(chatId, 'admitted');
    audio.add(
      RecordedAudio(path: path, duration: duration, waveform: waveform),
    );
  }

  @override
  Future<void> sendImages(
    String chatId,
    List<String> paths, {
    String? replyToMessageId,
  }) async {
    expect(chatId, 'admitted');
    images.add(List.of(paths));
  }

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) async {
    expect(chatId, 'admitted');
    sent.add(text);
  }
}

class _ChatsRepository extends MockChatsRepository {
  Set<String> deletedIds = {};
  Completer<void>? deletion;
  @override
  Future<void> deleteChats(Set<String> ids) async {
    deletedIds = {...ids};
    if (deletion != null) await deletion!.future;
  }

  @override
  Stream<Chat?> watchChat(String chatId) => const Stream.empty();
  @override
  Future<String?> resolveAvatar(Chat chat) async => null;
}

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(session: AuthSession(userId: 'me'));
  @override
  Stream<AuthState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements IAudioPlayerRepository {
  @override
  IAudioPlayerSession createSession() => _Session();
}

class _Session implements IAudioPlayerSession {
  @override
  Stream<AudioPlaybackSnapshot> get snapshots => const Stream.empty();
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recorder implements IAudioRecorderRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements ILocalMediaRepository {
  @override
  RecordedAudio? getVoiceDraft(String chatId) => null;
  @override
  Future<String?> consumePendingMedia() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryMedia extends _Media {
  _RecoveryMedia(this.path);
  final String path;
  int consumed = 0;
  @override
  List<String> getRecentMediaPaths() => [path];
  @override
  Future<String?> consumePendingMedia() async {
    consumed++;
    return consumed == 1 ? path : null;
  }
}

class _VoiceDraftMedia extends _Media {
  _VoiceDraftMedia(this.audio);
  final RecordedAudio audio;
  int removals = 0;
  @override
  RecordedAudio? getVoiceDraft(String chatId) => audio;
  @override
  Future<void> removeVoiceDraft(String chatId, {bool deleteFile = true}) async {
    removals++;
  }
}

class _Config implements AppConfig {
  @override
  final talker = Talker(settings: TalkerSettings(enabled: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
