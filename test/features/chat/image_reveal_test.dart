import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';

void main() {
  testWidgets('upload path replacement keeps the previous photo visible', (
    tester,
  ) async {
    const local = '/test/upload-draft-original.jpg';
    const stored = '/test/upload-cache-prepared.jpg';
    final cache = PaintingBinding.instance.imageCache;
    final oldImage = _decodedImage(Colors.red);
    final prepared = Completer<ImageInfo>();
    addTearDown(() {
      if (!prepared.isCompleted) {
        prepared.complete(ImageInfo(image: oldImage.clone()));
      }
      cache.clear();
      cache.clearLiveImages();
      oldImage.dispose();
    });
    for (final path in [local, stored]) {
      final key = await chatMediaImageProvider(
        path,
        cacheWidth: 100,
      ).obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          path == local
              ? SynchronousFuture(ImageInfo(image: oldImage.clone()))
              : prepared.future,
        ),
      );
    }
    final capture = GlobalKey();
    Widget mount(String path) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.blue,
        body: RepaintBoundary(
          key: capture,
          child: SizedBox.square(
            dimension: 100,
            child: ChatMediaImage(
              path: path,
              fit: BoxFit.cover,
              cacheWidth: 100,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(mount(local));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(ChatMediaImage));
    await tester.pumpWidget(mount(stored));
    for (final ms in [0, 16, 180, 300]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(tester.state(find.byType(ChatMediaImage)), same(state));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final red = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final value = rgba.getUint8((50 * image.width + 50) * 4);
        image.dispose();
        return value;
      });
      expect(red, 244, reason: 'retained photo must not become transparent');
    }
    prepared.complete(ImageInfo(image: _decodedImage(Colors.green)));
    await tester.pumpAndSettle();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chat media reveals only while its first frame is cold', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMediaImage(path: 'photo.jpg', fit: BoxFit.cover),
              ChatMediaImage(
                path: 'hero-photo.jpg',
                fit: BoxFit.cover,
                revealOnLoad: false,
              ),
            ],
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images[0].frameBuilder, isNotNull);
    expect(images[1].frameBuilder, isNotNull);
    const child = SizedBox();
    expect(
      images[1].frameBuilder!(
        tester.element(find.byType(ChatMediaImage).at(1)),
        child,
        null,
        false,
      ),
      same(child),
    );
  });

  testWidgets('chat media does not replay reveal for an already shown path', (
    tester,
  ) async {
    const path = 'remembered-chat-photo.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMediaImage(path: path, fit: BoxFit.cover),
        ),
      ),
    );

    final context = tester.element(find.byType(ChatMediaImage));
    final firstBuilder = tester.widget<Image>(find.byType(Image)).frameBuilder!;
    final waiting =
        firstBuilder(context, const SizedBox(), null, false) as AnimatedOpacity;
    expect(waiting.opacity, 0);
    firstBuilder(context, const SizedBox(), 0, false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMediaImage(path: path, fit: BoxFit.cover),
        ),
      ),
    );
    final nextBuilder = tester.widget<Image>(find.byType(Image)).frameBuilder!;
    final restored =
        nextBuilder(
              tester.element(find.byType(ChatMediaImage)),
              const SizedBox(),
              null,
              false,
            )
            as AnimatedOpacity;
    expect(restored.opacity, 1);
    expect(restored.duration, Duration.zero);
  });

  testWidgets(
    'restores a decoded thumbnail from Flutter image cache synchronously',
    (tester) async {
      const path = '/test/flutter-cached-thumbnail.jpg';
      final decoded = _decodedImage();
      addTearDown(decoded.dispose);
      final cache = PaintingBinding.instance.imageCache;
      addTearDown(() {
        cache.clear();
        cache.clearLiveImages();
      });
      final provider = chatMediaImageProvider(path, cacheWidth: 100);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final completer = OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: decoded.clone())),
      );
      cache.putIfAbsent(key, () => completer);
      await tester.pumpWidget(_thumbnail(path));
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(decoded),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cache.statusForKey(key).keepAlive, isTrue);
      await tester.pumpWidget(_thumbnail(path));
      // A real cached frame is present on the first build, without a delay or a
      // separate retained-frame overlay. No filesystem/network load is needed.
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(decoded),
        isTrue,
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
        Duration.zero,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(completer.hasListeners, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an evicted thumbnail waits for its new frame without retaining old pixels',
    (tester) async {
      const path = '/test/evicted-thumbnail.jpg';
      final cache = PaintingBinding.instance.imageCache;
      addTearDown(() {
        cache.clear();
        cache.clearLiveImages();
      });
      final provider = chatMediaImageProvider(path, cacheWidth: 100);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: _decodedImage())),
        ),
      );
      await tester.pumpWidget(_thumbnail(path));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cache.evict(key), isTrue);
      final pending = Completer<ImageInfo>();
      cache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(pending.future),
      );
      await tester.pumpWidget(_thumbnail(path));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
      pending.complete(ImageInfo(image: _decodedImage()));
      await tester.pumpAndSettle();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile photos reveal after their first decoded frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePhotoImage(
            photo: ProfilePhoto(
              position: 0,
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<Image>(find.byType(Image)).frameBuilder, isNotNull);
  });
}

Widget _thumbnail(String path) => MaterialApp(
  home: Scaffold(
    body: SizedBox.square(
      dimension: 100,
      child: ChatMediaImage(path: path, fit: BoxFit.cover, cacheWidth: 100),
    ),
  ),
);

ui.Image _decodedImage([Color color = Colors.blue]) {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(100, 100);
  picture.dispose();
  return image;
}
