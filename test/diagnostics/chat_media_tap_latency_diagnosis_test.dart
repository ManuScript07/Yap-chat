import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_hero.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_aspect_ratio_cache.dart';
import 'package:yap_chat/features/chat/widgets/message_media_grid.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';

// Diagnosis only. These opt-in probes measure the current interaction path;
// they do not claim to fix the native player or device frame scheduling.
void main() => runMediaTapDiagnostics();

void runMediaTapDiagnostics({Widget Function(Widget)? wrapList}) {
  for (final type in [MessageType.audio, MessageType.image]) {
    for (final imageReady
        in type == MessageType.image ? [true, false] : [true]) {
      for (final reactions in [false, true]) {
        testWidgets(
          'diagnostic media tap $type reactions=$reactions imageReady=$imageReady',
          (tester) async {
            chatMediaAspectRatios.clear();
            addTearDown(chatMediaAspectRatios.clear);
            final player = _Player(tester);
            final observer = _Routes(tester);
            const path = '/diagnostic/cached-photo.jpg';
            if (type == MessageType.image) {
              final recorder = ui.PictureRecorder();
              Canvas(
                recorder,
              ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
              final picture = recorder.endRecording();
              final image = picture.toImageSync(2, 2);
              picture.dispose();
              if (!imageReady) addTearDown(image.dispose);
              // Use exactly the thumbnail key the real grid resolves. No file or
              // network IO is involved in the already-decoded image scenario.
              final provider = chatMediaImageProvider(path, cacheWidth: 882);
              final key = await provider.obtainKey(ImageConfiguration.empty);
              PaintingBinding.instance.imageCache.putIfAbsent(
                key,
                () => OneFrameImageStreamCompleter(
                  imageReady
                      ? SynchronousFuture(ImageInfo(image: image))
                      : Completer<ImageInfo>().future,
                ),
              );
              addTearDown(() => PaintingBinding.instance.imageCache.clear());
            }
            final message = ChatMessage(
              id: 'media',
              chatId: 'chat',
              senderId: 'peer',
              text: '',
              timestamp: DateTime(2026),
              isMine: false,
              type: type,
              audioUrl: '/diagnostic/cached-voice.aac',
              audioDuration: const Duration(seconds: 5),
              mediaUrls: const [path],
            );
            await tester.pumpWidget(
              BlocProvider<AuthBloc>.value(
                value: _Auth(),
                child: RepositoryProvider<IAudioPlayerRepository>.value(
                  value: player,
                  child: MaterialApp(
                    navigatorObservers: [observer],
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: Scaffold(
                      body: Center(
                        child: (wrapList ?? (child) => child)(
                          MessageBubble(
                            message: message,
                            initialAnimationProgress: 1,
                            maxWidth: 300,
                            peerName: 'Peer',
                            onReaction: reactions ? (_, _) {} : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final target = type == MessageType.audio
                ? find.byIcon(Icons.play_arrow_rounded)
                : find
                      .descendant(
                        of: find.byType(MessageMediaGrid),
                        matching: find.byType(InkWell),
                      )
                      .first;
            final started = tester.binding.clock.now();
            await tester.tap(target);
            Duration? latency;
            for (var frame = 0; frame < 100; frame++) {
              await tester.pump(const Duration(milliseconds: 10));
              final time = type == MessageType.audio
                  ? player.playedAt
                  : observer.galleryAt;
              if (time != null) {
                latency = time.difference(started);
                break;
              }
            }
            // ignore: avoid_print
            print(
              'MEDIA_TAP type=$type reactions=$reactions imageReady=$imageReady latencyMs=${latency?.inMilliseconds}',
            );
            expect(latency, isNotNull);
            // Voice controls do not take part in double-tap reactions. Photos
            // still do, but missing dimensions never delay opening the route.
            final expectedLatency = type == MessageType.image && reactions
                ? 300
                : 0;
            expect(latency!.inMilliseconds, expectedLatency);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
          skip: !const bool.fromEnvironment('CHAT_FOLLOWUP_DIAGNOSTIC'),
        );
      }
    }
  }
}

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(session: AuthSession(userId: 'me'));
  @override
  Stream<AuthState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes extends NavigatorObserver {
  _Routes(this.tester);
  final WidgetTester tester;
  DateTime? galleryAt;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) galleryAt = tester.binding.clock.now();
    super.didPush(route, previousRoute);
  }
}

class _Player implements IAudioPlayerRepository {
  _Player(this.tester);
  final WidgetTester tester;
  DateTime? playedAt;
  @override
  IAudioPlayerSession createSession() => _Session(this);
}

class _Session implements IAudioPlayerSession {
  _Session(this.player);
  final _Player player;
  @override
  Stream<AudioPlaybackSnapshot> get snapshots => const Stream.empty();
  @override
  Future<void> play(String url) async {
    player.playedAt = player.tester.binding.clock.now();
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
