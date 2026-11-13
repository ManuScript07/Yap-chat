import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_aspect_ratio_cache.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_hero.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_gallery_page.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

void main() {
  test(
    'ratio metadata has bounded LRU retention and rejects invalid sizes',
    () {
      final cache = ChatMediaAspectRatioCache(capacity: 2);
      cache.remember('a', 2);
      cache.remember('b', 3);
      expect(cache.lookup('a'), 2);
      cache.remember('c', 4);
      expect(cache.lookup('b'), isNull);
      expect(cache.lookup('a'), 2);
      for (final value in [0.0, -1.0, double.nan, double.infinity]) {
        cache.remember('a', value);
      }
      expect(cache.lookup('a'), 2);
      cache.clear();
      expect(cache.lookup('a'), isNull);
    },
  );

  testWidgets('visible image shares decode and records metadata once', (
    tester,
  ) async {
    _reset(tester);
    const path = '/test/ratio-thumbnail.jpg';
    final completer = await _seed(
      path,
      300,
      SynchronousFuture(ImageInfo(image: _image(400, 100))),
    );
    final values = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: ChatMediaImage(
            path: path,
            fit: BoxFit.cover,
            cacheWidth: 300,
            onAspectRatio: values.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(values, [4]);
    expect(chatMediaAspectRatios.lookup(path), 4);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNotNull);
    expect(completer.hasListeners, isTrue); // Display, not a second image load.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(completer.hasListeners, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending image detaches metadata callbacks when disposed', (
    tester,
  ) async {
    _reset(tester);
    const path = '/test/disposed-thumbnail.jpg';
    final gate = Completer<ImageInfo>();
    await _seed(path, 300, gate.future);
    final values = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMediaImage(
          path: path,
          fit: BoxFit.cover,
          cacheWidth: 300,
          onAspectRatio: values.add,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    gate.complete(ImageInfo(image: _image(400, 100)));
    await tester.pumpAndSettle();
    expect(values, isEmpty);
    expect(chatMediaAspectRatios.lookup(path), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata does not attach to an image before its first frame', (
    tester,
  ) async {
    _reset(tester);
    const path = '/test/counting-thumbnail.jpg';
    final provider = chatMediaImageProvider(path, cacheWidth: 300);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final stream = _CountingImageStream();
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => stream);
    final cacheListeners = stream.listeners;
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatMediaImage(path: path, fit: BoxFit.cover, cacheWidth: 300),
      ),
    );
    expect(stream.listeners, cacheListeners + 1); // Only the displaying Image.
    expect(chatMediaAspectRatios.lookup(path), isNull);
    stream.complete(ImageInfo(image: _image(400, 100)));
    await tester.pumpAndSettle();
    expect(chatMediaAspectRatios.lookup(path), 4);
    expect(
      stream.listeners,
      1,
    ); // Metadata and cache's pending listener detach.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(stream.listeners, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late dimensions do not resize hero during route flight', (
    tester,
  ) async {
    _reset(tester);
    const path = '/test/late-thumbnail.jpg';
    final gate = Completer<ImageInfo>();
    await _seed(path, 320, gate.future);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey('open'),
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(milliseconds: 260),
                    pageBuilder: (_, _, _) => ChatMediaGalleryPage(
                      imagePaths: const [path],
                      heroTags: const ['late'],
                      initialIndex: 0,
                      initialThumbnailCacheWidth: 320,
                      senderName: 'Sender',
                      sentAt: DateTime(2026),
                    ),
                  ),
                ),
                child: const SizedBox(
                  width: 160,
                  height: 120,
                  child: ChatMediaHero(
                    path: path,
                    heroTag: 'late',
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final destination = find.byWidgetPredicate(
      (w) => w is ChatMediaHero && w.fit == BoxFit.contain,
    );
    final initialSize = tester.getSize(destination);
    expect(initialSize, tester.getSize(find.byType(PageView)));
    final heroModes = find.ancestor(
      of: destination,
      matching: find.byType(HeroMode),
    );
    expect(tester.widget<HeroMode>(heroModes.first).enabled, isFalse);
    gate.complete(ImageInfo(image: _image(400, 100)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(destination), initialSize);
    await tester.pumpAndSettle();
    expect(tester.getSize(destination).aspectRatio, closeTo(4, .001));
    expect(tester.widget<HeroMode>(heroModes.first).enabled, isTrue);
    Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _reset(WidgetTester tester) {
  chatMediaAspectRatios.clear();
  addTearDown(() {
    chatMediaAspectRatios.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

Future<ImageStreamCompleter> _seed(
  String path,
  int width,
  Future<ImageInfo> image,
) async {
  final provider = chatMediaImageProvider(path, cacheWidth: width);
  final key = await provider.obtainKey(ImageConfiguration.empty);
  return PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(image),
  )!;
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

class _CountingImageStream extends ImageStreamCompleter {
  int listeners = 0;
  @override
  void addListener(ImageStreamListener listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners--;
    super.removeListener(listener);
  }

  void complete(ImageInfo image) => setImage(image);
}
