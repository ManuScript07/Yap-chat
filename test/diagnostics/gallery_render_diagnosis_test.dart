import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

// Reproduce visual layering and clipping policy, not device GPU performance.
void main() {
  testWidgets('portrait chrome stays hidden through flight then fades in once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const path = '/diagnostic/red-portrait.jpg';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 200, 400),
      Paint()..color = Colors.red,
    );
    final picture = recorder.endRecording();
    final red = picture.toImageSync(200, 400);
    picture.dispose();
    for (final width in <int?>[320, null]) {
      final provider = chatMediaImageProvider(path, cacheWidth: width);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: red.clone())),
        ),
      );
    }
    red.dispose();
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      chatMediaAspectRatios.clear();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  key: const ValueKey('open'),
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      transitionDuration: const Duration(milliseconds: 260),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 180,
                      ),
                      pageBuilder: (_, _, _) => ChatMediaGalleryPage(
                        imagePaths: const [path],
                        heroTags: const ['portrait'],
                        initialIndex: 0,
                        initialThumbnailCacheWidth: 320,
                        senderName: 'Sender',
                        sentAt: DateTime(2026),
                        imageAspectRatios: const [.5],
                      ),
                      transitionsBuilder: (_, animation, _, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                  ),
                  child: const SizedBox(
                    width: 160,
                    height: 120,
                    child: ChatMediaHero(
                      path: path,
                      heroTag: 'portrait',
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final flight = find.byWidgetPredicate(
      (w) =>
          w is ClipRRect &&
          w.child is ColoredBox &&
          (w.child! as ColoredBox).child is ChatMediaImage,
    );
    expect(flight, findsOneWidget);
    // The real gallery avatar occupies x=72..116, y=16..60 at zero system inset.
    const avatarCenter = Offset(94, 38);
    expect(tester.getRect(flight).contains(avatarCenter), isTrue);
    final header = find.ancestor(
      of: find.text('Sender'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(header).opacity, 0);
    // Finish the flight: the header must still start at zero opacity, rather
    // than already being painted underneath the disappearing Hero overlay.
    await tester.pump(const Duration(milliseconds: 41));
    await tester.pump();
    final headerChild = tester.widget<AnimatedOpacity>(header).child;
    final fade = find.byWidgetPredicate(
      (widget) =>
          widget is FadeTransition && identical(widget.child, headerChild),
    );
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 70));
    final halfway = tester.widget<FadeTransition>(fade.first).opacity.value;
    expect(halfway, inExclusiveRange(0, 1));
    final partial = await _pixel(tester, boundary, avatarCenter);
    await tester.pumpAndSettle();
    final after = await _pixel(tester, boundary, avatarCenter);
    // ignore: avoid_print
    print('GALLERY_HEADER_PIXEL partial=$partial after=$after');
    expect(partial, isNot([244, 67, 54, 255]));
    expect(partial, isNot(after));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, skip: !const bool.fromEnvironment('GALLERY_RENDER_DIAGNOSTIC'));

  testWidgets('diagnostic profile pop has a fixed inner corner mask', (
    tester,
  ) async {
    final photo = ProfilePhoto(position: 0, bytes: Uint8List.fromList([0]));
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: GestureDetector(
              key: const ValueKey('open'),
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 260),
                  reverseTransitionDuration: const Duration(milliseconds: 180),
                  pageBuilder: (_, _, _) => ProfileGalleryPage(
                    photos: [photo],
                    initialIndex: 0,
                    initialThumbnailCacheWidth: 352,
                    displayName: 'User',
                    imageAspectRatios: const [2],
                  ),
                ),
              ),
              child: Center(
                child: SizedBox.square(
                  dimension: 176,
                  child: ProfilePhotoHero(
                    photo: photo,
                    borderRadius: 32,
                    cacheWidth: 352,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final outerFinder = find.byWidgetPredicate(
      (w) =>
          w is ClipRRect &&
          w.child is ClipRRect &&
          (w.child! as ClipRRect).child is ProfilePhotoImage,
    );
    final outer = tester.widget<ClipRRect>(outerFinder);
    final inner = outer.child! as ClipRRect;
    final animatedRadius = outer.borderRadius
        .resolve(TextDirection.ltr)
        .topLeft
        .x;
    final fixedRadius = inner.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    // ignore: avoid_print
    print('PROFILE_POP_RADIUS outer=$animatedRadius inner=$fixedRadius');
    expect(animatedRadius, inExclusiveRange(0, 32));
    expect(fixedRadius, 32);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('GALLERY_RENDER_DIAGNOSTIC'));
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey key,
  Offset point,
) async {
  final box = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await box.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final index = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
    final result = bytes.buffer.asUint8List().sublist(index, index + 4);
    image.dispose();
    return result;
  }))!;
}
