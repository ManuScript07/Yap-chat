import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  setUpAll(() async {
    for (final family in ['Roboto', 'RobotoFlex']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final opacity in [0.0, .25, 1.0]) {
    for (final pixelRatio in [1.0, 3.0]) {
      for (final width in [320.0, 780.0]) {
        testWidgets(
          'single smooth glow width=$width opacity=$opacity dpr=$pixelRatio',
          (tester) async {
            final key = GlobalKey();
            await tester.pumpWidget(_app(key, width: width, opacity: opacity));
            final pixels = await _capture(tester, key, pixelRatio: pixelRatio);
            final w = (width * pixelRatio).toInt();
            final h = (260 * pixelRatio).toInt();
            final profile = [
              for (var y = 0; y < h; y++) pixels[(y * w + w ~/ 2) * 4 + 3],
            ];
            var largestStep = 0;
            var upperFalloff = 0;
            for (var y = 0; y < h; y++) {
              if (y > 0) {
                final step = (profile[y] - profile[y - 1]).abs();
                if (step > largestStep) largestStep = step;
                expect(profile[y], greaterThanOrEqualTo(profile[y - 1] - 1));
              }
              final samples = [
                for (final x in [1, w ~/ 4, w ~/ 2, w - 2])
                  pixels[(y * w + x) * 4 + 3],
              ];
              // The old rounded contour needs lateral fading, not a flat
              // horizontal stripe. Symmetric edges remain balanced.
              expect(
                (samples.first - samples.last).abs(),
                lessThanOrEqualTo(2),
              );
              expect(samples[2], greaterThanOrEqualTo(samples.first - 1));
              if (y < h - 90 * pixelRatio) {
                final falloff = samples[2] - samples.first;
                if (falloff > upperFalloff) upperFalloff = falloff;
              }
            }
            debugPrint(
              'GLOW_PROFILE width=$width opacity=$opacity dpr=$pixelRatio max=${profile.reduce((a, b) => a > b ? a : b)} step=$largestStep upperFalloff=$upperFalloff',
            );
            expect(profile.first, 0);
            expect(
              profile.reduce((a, b) => a > b ? a : b),
              lessThanOrEqualTo((255 * opacity).ceil() + 1),
            );
            if (opacity == 0) {
              expect(pixels.where((value) => value != 0), isEmpty);
            }
            // No narrow extra band; the original rounded silhouette remains.
            expect(largestStep, lessThanOrEqualTo(4));
            if (opacity > 0) expect(upperFalloff, greaterThan(2));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final width in [320.0, 780.0]) {
    for (final pixelRatio in [1.0, 3.0]) {
      testWidgets(
        'original upper halo and height width=$width dpr=$pixelRatio',
        (tester) async {
          final key = GlobalKey();
          await tester.pumpWidget(
            _app(key, width: width, opacity: 1, glow: _referenceGlow()),
          );
          final reference = await _capture(tester, key, pixelRatio: pixelRatio);
          await tester.pumpWidget(_app(key, width: width, opacity: 1));
          final pixels = await _capture(tester, key, pixelRatio: pixelRatio);
          final extent = find.descendant(
            of: find.byType(BottomAmbientGlow),
            matching: find.byWidgetPredicate(
              (widget) => widget is SizedBox && widget.height == 180,
            ),
          );
          final glowRect = tester.getRect(extent);
          final frame = tester.getRect(find.byKey(key));
          expect(glowRect.height, 180);
          expect(glowRect.bottom, frame.bottom);
          final w = (width * pixelRatio).toInt();
          var largestDifference = 0;
          // Above the core, use the original rendering as the reference, not
          // a newly invented ellipse or a uniform rectangular fade.
          for (var y = 0; y < (260 - 63) * pixelRatio; y++) {
            for (var x = 0; x < w; x++) {
              final index = (y * w + x) * 4 + 3;
              final difference = (reference[index] - pixels[index]).abs();
              if (difference > largestDifference) {
                largestDifference = difference;
              }
            }
          }
          expect(largestDifference, 0);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('bright base matches reference RGB on black without a band', (
    tester,
  ) async {
    final key = GlobalKey();
    const color = Color(0xff03a6e1);
    Widget frame(Widget glow) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 360,
          height: 300,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(color: Colors.black, child: glow),
          ),
        ),
      ),
    );
    await tester.pumpWidget(frame(_referenceGlow(color: color)));
    final before = await _capture(tester, key, pixelRatio: 1);
    await tester.pumpWidget(frame(const BottomAmbientGlow(glowColor: color)));
    final after = await _capture(tester, key, pixelRatio: 1);
    for (final x in [10, 54, 180, 306, 349]) {
      for (final distance in [3, 9, 18, 30, 45, 63, 90]) {
        final index = ((299 - distance) * 360 + x) * 4;
        final green = after[index + 1];
        final oldGreen = before[index + 1];
        debugPrint(
          'GLOW_REFERENCE_RGB x=$x d=$distance before=$oldGreen after=$green',
        );
        expect(green, greaterThanOrEqualTo(oldGreen * .9 - 2));
        expect(green, lessThanOrEqualTo(oldGreen * 1.18 + 3));
        if (distance == 3) {
          expect(green, greaterThanOrEqualTo(150));
          expect(after[index + 2], greaterThanOrEqualTo(203));
        }
      }
      var previousStep = 0;
      for (var y = 160; y < 298; y++) {
        final current = after[(y * 360 + x) * 4 + 1];
        final next = after[((y + 1) * 360 + x) * 4 + 1];
        final step = next - current;
        // A narrow extra strip had an abrupt slope at its upper boundary.
        expect((step - previousStep).abs(), lessThanOrEqualTo(3));
        previousStep = step;
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('glow does not intercept touches or move during resize', (
    tester,
  ) async {
    var taps = 0;
    Widget page(double width) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 260,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                ),
              ),
              const Positioned.fill(child: BottomAmbientGlow()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(320));
    await tester.tapAt(
      tester.getBottomRight(find.byType(BottomAmbientGlow)) -
          const Offset(12, 12),
    );
    expect(taps, 1);
    await tester.pumpWidget(page(600));
    expect(
      tester.getSize(find.byType(BottomAmbientGlow)),
      const Size(600, 260),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('real search and navigation keep the bright base visible', (
    tester,
  ) async {
    final key = GlobalKey();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.brandPrimary,
            surface: Colors.white,
            onSurface: AppColors.textPrimary,
            outline: AppColors.borderInactive,
          ),
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 300),
            padding: EdgeInsets.only(bottom: 14),
            viewPadding: EdgeInsets.only(bottom: 14),
          ),
          child: Center(
            child: SizedBox(
              width: 360,
              height: 300,
              child: RepaintBoundary(
                key: key,
                child: Material(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      const Positioned.fill(child: BottomAmbientGlow()),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 116,
                        child: GlassSearchBar(
                          hintText: 'поиск по чатам',
                          focusNode: focus,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: FloatingNavigationBar(
                          activeIndex: 0,
                          onTap: (_) {},
                          items: const [
                            FloatingNavigationBarItem(
                              icon: Icons.sms_outlined,
                              activeIcon: Icons.sms_rounded,
                              label: 'чатикс',
                            ),
                            FloatingNavigationBarItem(
                              icon: Icons.place_outlined,
                              activeIcon: Icons.place,
                              label: 'рядом',
                            ),
                            FloatingNavigationBarItem(
                              icon: Icons.mood_outlined,
                              activeIcon: Icons.emoji_emotions,
                              label: 'друны',
                            ),
                            FloatingNavigationBarItem(
                              icon: Icons.person_outline_rounded,
                              activeIcon: Icons.person_rounded,
                              label: 'акк',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pixels = await _capture(tester, key, pixelRatio: 1);
    for (final x in [10, 349]) {
      final index = ((299 - 3) * 360 + x) * 4;
      expect(pixels[index + 1], greaterThanOrEqualTo(150));
      expect(pixels[index + 2], greaterThanOrEqualTo(203));
    }
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/glow_restored_preview.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  GlobalKey key, {
  required double width,
  required double opacity,
  Widget? glow,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: width,
      height: 260,
      child: RepaintBoundary(
        key: key,
        child:
            glow ??
            BottomAmbientGlow(
              glowColor: const Color(0xff0088ff),
              opacity: opacity,
            ),
      ),
    ),
  ),
);

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key, {
  required double pixelRatio,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = Uint8List.fromList(data!.buffer.asUint8List());
    image.dispose();
    return bytes;
  }))!;
}

// Unmodified halo and narrow core from the original production widget.
Widget _referenceGlow({Color color = const Color(0xff0088ff)}) => IgnorePointer(
  child: Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      width: double.infinity,
      height: 180,
      child: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 60,
                sigmaY: 24,
                tileMode: ui.TileMode.decal,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      color,
                      color.withValues(alpha: .6),
                      color.withValues(alpha: .15),
                      color.withValues(alpha: 0),
                    ],
                    stops: const [0, .4, .6, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [color, color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
