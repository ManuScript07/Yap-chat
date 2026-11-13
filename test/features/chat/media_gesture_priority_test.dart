import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/audio_waveform.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_gallery_page.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/features/chat/widgets/message_media_grid.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';

void main() {
  for (final size in [const Size(390, 780), const Size(780, 390)]) {
    testWidgets(
      'voice play/pause and seeking do not wait for reactions $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final session = _Session();
        var reactions = 0;
        await _mount(
          tester,
          MessageType.audio,
          session: session,
          onReaction: (_, _) => reactions++,
        );
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pump();
        expect(session.playCount, 1);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await tester.pump();
        expect(session.pauseCount, 1);
        expect(reactions, 0);
        await tester.tap(find.byType(AudioWaveform));
        await tester.pump();
        expect(session.prepareCount, 1);
        expect(session.seeks.single.inMilliseconds, closeTo(2500, 50));
        final waveform = tester.getRect(find.byType(AudioWaveform));
        await tester.dragFrom(
          waveform.centerLeft + const Offset(10, 0),
          const Offset(80, 0),
        );
        await tester.pump();
        expect(session.prepareCount, 2);
        expect(session.seeks, hasLength(2));
        expect(reactions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final type in [
    MessageType.audio,
    MessageType.image,
    MessageType.location,
  ]) {
    testWidgets(
      'double tap on $type keeps its reaction without opening media',
      (tester) async {
        var reactions = 0;
        final session = _Session();
        final launches = <MethodCall>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            launches.add(call);
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await _mount(
          tester,
          type,
          session: session,
          onReaction: (code, _) {
            expect(code, ReactionCode.heart);
            reactions++;
          },
        );
        final target = switch (type) {
          MessageType.audio => find.text('00:05'),
          MessageType.image => find.byType(MessageMediaGrid),
          _ => find.byIcon(Icons.location_on_rounded),
        };
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(reactions, 1);
        expect(launches, isEmpty);
        expect(session.playCount, 0);
        expect(find.byType(ChatMediaGalleryPage), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final onControl in [true, false]) {
    testWidgets('voice long press retains message menu onControl=$onControl', (
      tester,
    ) async {
      final session = _Session();
      var menus = 0;
      var reactions = 0;
      await _mount(
        tester,
        MessageType.audio,
        session: session,
        onReaction: (_, _) => reactions++,
        onLongPress: (_) => menus++,
      );
      await tester.longPress(
        onControl ? find.byIcon(Icons.play_arrow_rounded) : find.text('00:05'),
      );
      await tester.pumpAndSettle();
      expect(menus, 1);
      expect(session.playCount, 0);
      expect(reactions, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final control in ['play', 'waveform']) {
    testWidgets(
      'vertical scrolling starting on $control never starts audio or seeks',
      (tester) async {
        final session = _Session();
        var reactions = 0;
        await _mount(
          tester,
          MessageType.audio,
          session: session,
          scrollable: true,
          onReaction: (_, _) => reactions++,
        );
        final target = control == 'play'
            ? find.byIcon(Icons.play_arrow_rounded)
            : find.byType(AudioWaveform);
        await tester.drag(target, const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(session.playCount, 0);
        expect(session.prepareCount, 0);
        expect(session.seeks, isEmpty);
        expect(reactions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final reactions in [false, true]) {
    testWidgets(
      'location launch only waits for double tap reactions=$reactions',
      (tester) async {
        DateTime? launchedAt;
        final calls = <MethodCall>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            launchedAt = tester.binding.clock.now();
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await _mount(
          tester,
          MessageType.location,
          onReaction: reactions ? (_, _) {} : null,
        );
        final start = tester.binding.clock.now();
        await tester.tap(find.byIcon(Icons.location_on_rounded));
        await tester.pump();
        if (reactions) {
          expect(calls, isEmpty);
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(calls, hasLength(1));
        expect(calls.single.method, 'launch');
        expect(calls.single.arguments['url'], 'geo:55.75,37.61?q=55.75,37.61');
        expect(
          launchedAt!.difference(start).inMilliseconds,
          reactions ? 300 : 0,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  MessageType type, {
  _Session? session,
  void Function(ReactionCode, bool)? onReaction,
  ValueChanged<ChatMessage>? onLongPress,
  bool scrollable = false,
}) async {
  final bubble = MessageBubble(
    message: ChatMessage(
      id: 'media',
      chatId: 'chat',
      senderId: 'peer',
      text: '',
      timestamp: DateTime(2026),
      isMine: false,
      type: type,
      audioUrl: '/test/voice.aac',
      audioDuration: const Duration(seconds: 5),
      mediaUrls: const ['/test/missing.jpg'],
      latitude: 55.75,
      longitude: 37.61,
    ),
    initialAnimationProgress: 1,
    maxWidth: 300,
    peerName: 'Peer',
    onReaction: onReaction,
    onLongPress: onLongPress,
  );
  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: _Auth(),
      child: RepositoryProvider<IAudioPlayerRepository>.value(
        value: _Player(session ?? _Session()),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: scrollable
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      bubble,
                      const SizedBox(height: 1500),
                    ],
                  )
                : Center(child: bubble),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  _Player(this.session);
  final _Session session;
  @override
  IAudioPlayerSession createSession() => session;
}

class _Session implements IAudioPlayerSession {
  final _events = StreamController<AudioPlaybackSnapshot>.broadcast();
  int playCount = 0;
  int pauseCount = 0;
  int prepareCount = 0;
  final seeks = <Duration>[];
  @override
  Stream<AudioPlaybackSnapshot> get snapshots => _events.stream;
  @override
  Future<void> play(String url) async {
    playCount++;
    _events.add(const AudioPlaybackSnapshot(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _events.add(const AudioPlaybackSnapshot());
  }

  @override
  Future<void> prepare(String url) async {
    prepareCount++;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> dispose() => _events.close();
}
