import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

// Regression: the moving photo is ONE continuous field below real chat chrome.
// Sampling a vertical colour ramp detects stationary strips as well as black holes.
void main() {
  for (final (label, ratio, viewport, top) in [
    ('portrait', .5, const Size(390, 780), 110.0),
    ('landscape-photo', 2.0, const Size(390, 780), 110.0),
    ('landscape-screen', .5, const Size(780, 390), 110.0),
    ('source-under-header', .5, const Size(390, 780), -45.0),
    ('source-under-composer', .5, const Size(390, 780), 665.0),
  ]) {
    testWidgets('$label photo remains continuous under chat chrome', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(viewport);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        return tester.binding.setSurfaceSize(null);
      });
      final path = '/diagnostic/continuous-$label.jpg';
      final h = (200 / ratio).round();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, 200, h.toDouble()),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h.toDouble()), [
            const Color(0xffff0000),
            const Color(0xffffff00),
          ]),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(200, h);
      picture.dispose();
      for (final width in <int?>[220, 440, 660, 900, null]) {
        final provider = chatMediaImageProvider(path, cacheWidth: width);
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
            SynchronousFuture(ImageInfo(image: image.clone())),
          ),
        );
      }
      image.dispose();
      chatMediaAspectRatios.remember(path, ratio);
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        chatMediaAspectRatios.clear();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: Colors.black,
              colorScheme: const ColorScheme.dark(surface: Colors.white),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatMediaTransitionScope(
                child: Builder(
                  builder: (context) {
                    return Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xff202020)),
                        ),
                        Positioned(
                          top: top,
                          left: 90,
                          width: 220,
                          child: ColoredBox(
                            color: Colors.blue,
                            child: MessageMediaGrid(
                              message: ChatMessage(
                                id: 'photo',
                                chatId: 'chat',
                                senderId: 'peer',
                                text: '',
                                timestamp: DateTime(2026),
                                isMine: false,
                                type: MessageType.image,
                                mediaUrls: [path],
                              ),
                              maxWidth: 220,
                              senderName: 'Sender',
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: ChatMediaTransitionLayer(),
                        ),
                        const ChatMediaTransitionShadows(
                          topHeight: 84,
                          bottomHeight: 110,
                          backgroundColor: Colors.black,
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: ChatMediaTransitionChrome(
                            child: ChatAppBar(
                              userName: 'Chat peer',
                              isOnline: true,
                              onBack: () {},
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: ChatMediaTransitionChrome(
                            region: ChatMediaChromeRegion.composer,
                            child: SizedBox(
                              height: 90,
                              child: Row(
                                children: [
                                  const SizedBox(width: 16),
                                  GlassIconButton(
                                    icon: Icons.add,
                                    onTap: () {},
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: ChatGlassSurface(
                                      borderRadius: 24,
                                      child: SizedBox(
                                        height: 50,
                                        child: Center(
                                          child: Text('Draft input'),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 130,
                          right: 16,
                          child: ChatMediaTransitionChrome(
                            region: ChatMediaChromeRegion.scrollButton,
                            paintOutset: 8,
                            child: GlassIconButton(
                              icon: Icons.keyboard_arrow_down_rounded,
                              onTap: () {},
                              borderRadius: 36,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = tester.getRect(find.byType(MessageMediaGrid));
      final header = tester.element(find.byType(ChatAppBar));
      final input = tester.element(find.text('Draft input'));
      final geometry = ChatMediaTransitionScope.maybeOf(
        tester.element(find.byType(ChatAppBar)),
      )!;
      final initialOpacities = <double>[];
      void recordInitialOpacity() =>
          initialOpacities.add(geometry.localFlight.chromeOpacity.value);
      geometry.localFlight.chromeOpacity.addListener(recordInitialOpacity);
      final firstFramePoints = [
        const Offset(30, 30), // header/back button
        const Offset(10, 70), // top gradient tail
        Offset(10, viewport.height - 5), // bottom gradient
        Offset(30, viewport.height - 45), // bottom button
        Offset(viewport.width - 40, viewport.height - 160), // down button
      ];
      final initialPixels = [
        for (final point in firstFramePoints)
          await _pixel(tester, boundary, point),
      ];
      if (label == 'source-under-header') {
        await tester.tapAt(const Offset(200, 90));
      } else if (label == 'source-under-composer') {
        await tester.tapAt(const Offset(200, 675));
      } else {
        await tester.tap(
          find.descendant(
            of: find.byType(MessageMediaGrid),
            matching: find.byType(InkWell),
          ),
        );
      }
      await tester.pump();
      geometry.localFlight.chromeOpacity.removeListener(recordInitialOpacity);
      expect(
        initialOpacities,
        everyElement(closeTo(1, .001)),
        reason:
            'offstage measurement must not briefly hide chrome/shadows before time advances',
      );
      for (var i = 0; i < firstFramePoints.length; i++) {
        expect(
          await _pixel(tester, boundary, firstFramePoints[i]),
          initialPixels[i],
          reason:
              'first painted frame must retain chrome and shadows, point=$i',
        );
      }
      var samples = 0;
      final shadowPoints = [
        const Offset(10, 12),
        Offset(10, viewport.height - 5),
      ];
      final previousShadowPixels = [
        for (final point in shadowPoints) await _pixel(tester, boundary, point),
      ];
      final closingShadowPixels = <int, List<int>>{};
      Future<void> checkFrame() async {
        final gallery = find.byType(ChatMediaGalleryPage);
        final route = ModalRoute.of(tester.element(gallery))!;
        expect(geometry.localFlight.isFlying, isTrue);
        expect(find.byType(ChatMediaFlightPhoto), findsOneWidget);
        final targetHero = find.descendant(
          of: gallery,
          matching: find.byType(ChatMediaHero),
        );
        final target = tester.getRect(targetHero);
        final rect = Rect.lerp(source, target, route.animation!.value)!;
        for (var i = 0; i < shadowPoints.length; i++) {
          if (rect.inflate(5).contains(shadowPoints[i])) continue;
          final pixel = await _pixel(tester, boundary, shadowPoints[i]);
          if (route.animation!.status == AnimationStatus.forward) {
            expect(
              pixel[0],
              lessThanOrEqualTo(previousShadowPixels[i][0] + 1),
              reason: 'opening must not brighten a shadow before darkening it',
            );
            previousShadowPixels[i] = pixel;
          } else {
            final previous = closingShadowPixels[i];
            if (previous != null) {
              expect(
                pixel[0],
                greaterThanOrEqualTo(previous[0] - 1),
                reason: 'closing must not darken a shadow before restoring it',
              );
            }
            closingShadowPixels[i] = pixel;
          }
        }
        final ys = [
          12.0,
          60.0,
          70.0,
          viewport.height - 186,
          viewport.height - 85,
          rect.top + rect.height * .25,
          rect.center.dy,
          rect.top + rect.height * .75,
        ];
        for (final y in ys) {
          for (final x in [300.0, 320.0]) {
            final point = Offset(x.floor() + .5, y.floor() + .5);
            if (!rect.deflate(5).contains(point) ||
                y < 0 ||
                y >= viewport.height) {
              continue;
            }
            // Avoid actual controls and their blur/shadow. Include the space
            // around the down button and above the composer, formerly masked.
            if (y >= viewport.height - 180 &&
                y <= viewport.height - 122 &&
                x >= 324) {
              continue;
            }
            if (y >= viewport.height - 78) continue;
            if (y < 58 && x >= 146) {
              continue; // actual header text, not bare photo
            }
            var shade = 1.0;
            if (point.dy < 84) shade *= point.dy / 84;
            if (point.dy > viewport.height - 110) {
              shade *= 1 - (point.dy - (viewport.height - 110)) / 110;
            }
            // Background gradients remain fixed. Only their portion over
            // the moving image fades with the existing chrome animation.
            shade = 1 - (1 - shade) * geometry.localFlight.chromeOpacity.value;
            final scale = (rect.width / 200) > (rect.height / h)
                ? rect.width / 200
                : rect.height / h;
            final naturalY = (point.dy - rect.center.dy) / scale + h / 2;
            final pixel = await _pixel(tester, boundary, point);
            expect(
              pixel[0],
              closeTo(255 * shade, 6),
              reason:
                  'black hole $label t=${route.animation!.value} p=$point rect=$rect',
            );
            expect(
              pixel[1],
              closeTo(255 * (naturalY / h).clamp(0, 1) * shade, 6),
              reason:
                  'image split $label t=${route.animation!.value} p=$point rect=$rect',
            );
            expect(
              pixel[2],
              lessThanOrEqualTo(3),
              reason: 'blue bubble exposed',
            );
            samples++;
          }
        }
        expect(tester.element(find.byType(ChatAppBar)), same(header));
        expect(tester.element(find.text('Draft input')), same(input));
        expect(tester.takeException(), isNull);
      }

      for (final step in [1, 8, 16, 16, 16, 16, 32, 32, 32, 32, 32, 24]) {
        await tester.pump(Duration(milliseconds: step));
        await checkFrame();
      }
      final handoffPoints = [
        const Offset(200, 70),
        Offset(200, viewport.height - 85),
        const Offset(320, 70),
        Offset(320, viewport.height - 85),
      ];
      final beforeHandoff = [
        for (final point in handoffPoints)
          await _pixel(tester, boundary, point),
      ];
      await tester.pump(const Duration(milliseconds: 8));
      expect(geometry.localFlight.isFlying, isFalse);
      for (var i = 0; i < handoffPoints.length; i++) {
        final pixel = await _pixel(tester, boundary, handoffPoints[i]);
        expect(
          pixel[0],
          closeTo(beforeHandoff[i][0], 2),
          reason:
              'photo must stay unchanged at the local flight -> gallery handoff',
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatMediaFlightPhoto), findsNothing);
      final fullscreenPhoto = tester.getRect(
        find.descendant(
          of: find.byType(ChatMediaGalleryPage),
          matching: find.byType(ChatMediaHero),
        ),
      );
      for (final point in handoffPoints) {
        if (!fullscreenPhoto.deflate(5).contains(point)) continue;
        final pixel = await _pixel(tester, boundary, point);
        expect(
          pixel[0],
          closeTo(255, 3),
          reason: 'fullscreen photo must not retain the chat edge gradients',
        );
      }
      if (label == 'source-under-composer') {
        // Hiding gallery controls must not create another shadow fade at pop.
        await tester.tapAt(viewport.center(Offset.zero));
        await tester.pumpAndSettle();
      }
      final beforePop = [
        for (final point in handoffPoints)
          await _pixel(tester, boundary, point),
      ];
      Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
      await tester.pump();
      for (var i = 0; i < handoffPoints.length; i++) {
        expect(
          await _pixel(tester, boundary, handoffPoints[i]),
          beforePop[i],
          reason:
              'gallery -> local photo handoff must not introduce edge shading',
        );
      }
      for (final step in [1, 8, 8, 16, 16, 16, 16, 16, 16, 16, 16, 16]) {
        await tester.pump(Duration(milliseconds: step));
        await checkFrame();
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatMediaGalleryPage), findsNothing);
      expect(geometry.localFlight.isFlying, isFalse);
      expect(geometry.localFlight.chromeOpacity.value, 1);
      expect(tester.getRect(find.byType(MessageMediaGrid)), source);
      expect(samples, greaterThan(40));
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print('CONTINUOUS_PHOTO $label samples=$samples');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, skip: !const bool.fromEnvironment('GALLERY_RENDER_DIAGNOSTIC'));
  }
}

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset point,
) async {
  final box =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await box.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
    final result = bytes.buffer.asUint8List().sublist(offset, offset + 4);
    image.dispose();
    return result;
  }))!;
}
