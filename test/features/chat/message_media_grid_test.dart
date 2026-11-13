import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';

void main() {
  for (final count in [1, 2, 5]) {
    testWidgets(
      '$count uploaded photos retain every tile through cache handoff',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.red, BlendMode.src);
        final picture = recorder.endRecording();
        final decoded = picture.toImageSync(200, 200);
        picture.dispose();
        final cache = PaintingBinding.instance.imageCache;
        final pending = <Completer<ImageInfo>>[];
        addTearDown(() {
          for (final completer in pending) {
            if (!completer.isCompleted) {
              completer.complete(ImageInfo(image: decoded.clone()));
            }
          }
          cache.clear();
          cache.clearLiveImages();
          decoded.dispose();
        });
        for (var i = 0; i < count; i++) {
          for (final width in [220, 109, 53]) {
            for (final sent in [false, true]) {
              final provider = chatMediaImageProvider(
                '/handoff/$count/${sent ? "cache" : "draft"}/$i.jpg',
                cacheWidth: width,
              );
              final key = await provider.obtainKey(ImageConfiguration.empty);
              final completer = Completer<ImageInfo>();
              if (sent) pending.add(completer);
              cache.putIfAbsent(
                key,
                () => OneFrameImageStreamCompleter(
                  sent
                      ? completer.future
                      : SynchronousFuture(ImageInfo(image: decoded.clone())),
                ),
              );
            }
          }
        }
        Widget mount(bool sent) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageMediaGrid(
                maxWidth: 220,
                senderName: 'Me',
                message: ChatMessage(
                  id: 'handoff-$count',
                  chatId: 'chat',
                  senderId: 'me',
                  text: '',
                  timestamp: DateTime(2026),
                  isMine: true,
                  type: MessageType.image,
                  status: sent ? MessageStatus.sent : MessageStatus.sending,
                  mediaUrls: [
                    for (var i = 0; i < count; i++)
                      '/handoff/$count/${sent ? "cache" : "draft"}/$i.jpg',
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(mount(false));
        await tester.pump(const Duration(milliseconds: 250));
        final states = [
          for (final element in find.byType(ChatMediaImage).evaluate())
            (element as StatefulElement).state,
        ];
        await tester.pumpWidget(mount(true));
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.byType(ChatMediaImage), findsNWidgets(count));
        for (var i = 0; i < count; i++) {
          final tile = find.byType(ChatMediaImage).at(i);
          expect(tester.state(tile), same(states[i]));
          final image = find.descendant(
            of: tile,
            matching: find.byType(RawImage),
          );
          expect(tester.widget<RawImage>(image).image, isNotNull);
          expect(
            tester
                .widget<AnimatedOpacity>(
                  find.descendant(
                    of: tile,
                    matching: find.byType(AnimatedOpacity),
                  ),
                )
                .opacity,
            1,
            reason: 'decoded draft must remain visible while cache file loads',
          );
        }
        for (final completer in pending) {
          completer.complete(ImageInfo(image: decoded.clone()));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  const masks = {
    1: [15],
    2: [5, 10],
    3: [5, 2, 8],
    4: [1, 2, 4, 8],
    5: [5, 0, 2, 0, 8],
  };
  for (final direction in TextDirection.values) {
    for (var count = 1; count <= 10; count++) {
      testWidgets('$count photos have only outer album corners ($direction)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MessageMediaGrid(
                    message: ChatMessage(
                      id: 'album',
                      chatId: 'chat',
                      senderId: 'sender',
                      text: '',
                      timestamp: DateTime(2026),
                      isMine: false,
                      type: MessageType.image,
                      mediaUrls: List.generate(count, (i) => 'photo-$i.jpg'),
                    ),
                    maxWidth: 200,
                    senderName: 'Sender',
                  ),
                ),
              ),
            ),
          ),
        );
        final heroes = tester
            .widgetList<ChatMediaHero>(find.byType(ChatMediaHero))
            .toList();
        expect(heroes, hasLength(count));
        for (var index = 0; index < count; index++) {
          final chunkStart = index ~/ 5 * 5;
          final chunkLength = (count - chunkStart).clamp(1, 5);
          final mask = masks[chunkLength]![index % 5];
          final actual = heroes[index].borderRadius.resolve(direction);
          final startTop = direction == TextDirection.ltr
              ? actual.topLeft
              : actual.topRight;
          final endTop = direction == TextDirection.ltr
              ? actual.topRight
              : actual.topLeft;
          final startBottom = direction == TextDirection.ltr
              ? actual.bottomLeft
              : actual.bottomRight;
          final endBottom = direction == TextDirection.ltr
              ? actual.bottomRight
              : actual.bottomLeft;
          expect(startTop.x, mask & 1 == 0 ? 0 : 20);
          expect(endTop.x, mask & 2 == 0 ? 0 : 20);
          expect(startBottom.x, mask & 4 == 0 ? 0 : 20);
          expect(endBottom.x, mask & 8 == 0 ? 0 : 20);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('decodes album thumbnails at their rendered tile width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageMediaGrid(
              message: ChatMessage(
                id: 'message-id',
                chatId: 'chat-id',
                senderId: 'sender-id',
                text: '',
                timestamp: DateTime(2026),
                isMine: false,
                type: MessageType.image,
                mediaUrls: const [
                  'first.jpg',
                  'second.jpg',
                  'third.jpg',
                  'fourth.jpg',
                ],
              ),
              maxWidth: 300,
              senderName: 'Sender',
            ),
          ),
        ),
      ),
    );

    final heroes = find.byType(ChatMediaHero);
    final widths = tester
        .widgetList<ChatMediaHero>(heroes)
        .map((hero) => hero.cacheWidth)
        .toList();
    expect(widths, hasLength(4));
    for (var index = 0; index < widths.length; index++) {
      final renderedWidth = tester.getSize(heroes.at(index)).width;
      final expected = (renderedWidth * tester.view.devicePixelRatio)
          .ceil()
          .clamp(1, 900);
      expect(widths[index], expected);
    }
  });
}
