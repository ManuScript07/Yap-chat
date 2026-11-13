import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';

const _color = Color(0xff03a6e1);

void main() {
  for (final size in [
    const Size(320, 360),
    const Size(390, 380),
    const Size(780, 180),
  ]) {
    for (final dpr in [1.0, 2.625, 3.0]) {
      testWidgets(
        'profile halo brightness, height and rounded falloff $size dpr=$dpr',
        (tester) async {
          final key = GlobalKey();
          Widget frame(Widget glow) => MaterialApp(
            theme: ThemeData(
              colorScheme: const ColorScheme.dark(primary: _color),
            ),
            home: Center(
              child: SizedBox(
                width: size.width,
                height: size.height + 60,
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Align(alignment: Alignment.topCenter, child: glow),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(frame(_legacyGlow(size.height)));
          final before = await _capture(tester, key, dpr, label: 'original');
          await tester.pumpWidget(
            frame(ProfileAmbientGlow(height: size.height)),
          );
          final after = await _capture(tester, key, dpr, label: 'restored');
          expect(tester.getSize(find.byType(ProfileAmbientGlow)), size);
          final w = (size.width * dpr).round();
          final h = ((size.height + 60) * dpr).ceil();
          int channel(List<int> data, double x, double y, int channel) =>
              data[((y * dpr).floor() * w + (x * dpr).floor()) * 4 + channel];
          final x = size.width / 2;
          expect(
            channel(after, x, 1, 1),
            greaterThan(channel(before, x, 1, 1) + 20),
          );
          expect(channel(after, x, 1, 1), closeTo(166, 2));
          expect(channel(after, x, 1, 2), closeTo(225, 2));
          // The former decal blur lost about half its alpha at both sides,
          // leaving dark patches just below the new bright core.
          for (final fraction in [.1, .2, .25]) {
            final center = channel(after, x, size.height * fraction, 1);
            for (final side in [
              1.0,
              8.0,
              size.width / 4,
              size.width - 9,
              size.width - 2,
            ]) {
              expect(
                channel(after, side, size.height * fraction, 1),
                closeTo(center, 5),
                reason: 'Upper glow must not have dark side patches.',
              );
            }
          }
          // A fixed layout height alone did not prevent the visible halo from
          // shrinking. No part of the old field may become darker, and its
          // original lower contour must survive, across the entire width.
          var largestDrop = 0;
          var largestTailDifference = 0;
          for (var row = 0; row < h; row++) {
            for (var col = 0; col < w; col++) {
              final offset = (row * w + col) * 4 + 1;
              final difference = before[offset] - after[offset];
              if (difference > largestDrop) largestDrop = difference;
              if (row >= size.height * .82 * dpr &&
                  difference.abs() > largestTailDifference) {
                largestTailDifference = difference.abs();
              }
            }
          }
          expect(largestDrop, lessThanOrEqualTo(2));
          expect(
            largestTailDifference,
            lessThanOrEqualTo(2),
            reason:
                'The original blurred bottom must not be replaced with a shorter mask.',
          );
          int lastVisibleRow(List<int> data, double column) {
            final col = (column * dpr).floor();
            for (var row = h - 1; row >= 0; row--) {
              if (data[(row * w + col) * 4 + 1] >= 5) return row;
            }
            return -1;
          }

          for (final column in [
            1.0,
            size.width * .1,
            size.width / 4,
            x,
            size.width * .75,
            size.width * .9,
            size.width - 2,
          ]) {
            expect(
              lastVisibleRow(after, column),
              closeTo(lastVisibleRow(before, column), 2 * dpr),
              reason:
                  'Visible height must match the old rounded contour at x=$column.',
            );
          }
          expect(
            lastVisibleRow(after, x),
            greaterThan(lastVisibleRow(after, 1) + 4 * dpr),
          );
          debugPrint(
            'PROFILE_HALO $size dpr=$dpr oldBottom=${lastVisibleRow(before, x) / dpr} newBottom=${lastVisibleRow(after, x) / dpr} tailDifference=$largestTailDifference',
          );
          expect(
            channel(after, x, size.height * .65, 1),
            greaterThanOrEqualTo(channel(before, x, size.height * .65, 1) - 2),
          );
          // At the lower edge the original blur gives a rounded, symmetric contour.
          final y = size.height * .75;
          expect(
            channel(after, x, y, 1),
            greaterThan(channel(after, 1, y, 1) + 5),
          );
          expect(
            channel(after, 1, y, 1),
            closeTo(channel(after, size.width - 2, y, 1), 2),
          );
          expect(channel(after, x, size.height + 50, 1), lessThanOrEqualTo(1));
          var maxStep = 0;
          var previous = channel(after, x, 1, 1);
          for (
            var row = (2 * dpr).round();
            row < ((size.height + 50) * dpr).floor();
            row++
          ) {
            final current = after[(row * w + w ~/ 2) * 4 + 1];
            // Compare farther apart than raster dithering's alternating rows.
            final earlier =
                after[((row - (16 * dpr).round()).clamp(0, row) * w + w ~/ 2) *
                        4 +
                    1];
            expect(current, lessThanOrEqualTo(earlier + 2));
            maxStep = (current - previous).abs() > maxStep
                ? (current - previous).abs()
                : maxStep;
            previous = current;
          }
          expect(
            maxStep,
            lessThanOrEqualTo(4),
            reason: 'No narrow bright/dark stripe.',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key,
  double ratio, {
  required String label,
}) async => (await tester.runAsync(() async {
  final image =
      await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage(pixelRatio: ratio);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = Uint8List.fromList(data!.buffer.asUint8List());
  if (ratio == 1 && Platform.environment['CAPTURE_PROFILE_GLOW'] == 'true') {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      'tmp/profile-glow-$label-${image.width}.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  }
  image.dispose();
  return bytes;
}))!;

Widget _legacyGlow(double height) => SizedBox(
  width: double.infinity,
  height: height,
  child: Stack(
    fit: StackFit.expand,
    children: [
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: 42,
          sigmaY: 18,
          tileMode: ui.TileMode.decal,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                for (final a in [.98, .86, .52, .1])
                  _color.withValues(alpha: a),
              ],
              stops: const [0, .22, .65, 1],
            ),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              for (final a in [.34, .22, 0.0]) _color.withValues(alpha: a),
            ],
            stops: const [0, .42, 1],
          ),
        ),
      ),
    ],
  ),
);
