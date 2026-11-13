import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

void main() {
  for (final size in [const Size(320, 720), const Size(780, 390)]) {
    testWidgets(
      'crop mask matches profile but exported corners remain intact $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final bytes = (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 64, 96),
            Paint()..color = Colors.white,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(64, 96);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final result = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
          return result;
        }))!;
        Uint8List? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await openProfilePhotoCropper(context, bytes);
                  },
                  child: const Text('crop'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('crop'));
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (find.byType(InteractiveViewer).evaluate().isNotEmpty &&
              tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((w) => w.image != null)) {
            break;
          }
        }
        await tester.pumpAndSettle();
        final cropRect = tester.getRect(find.byType(InteractiveViewer));
        expect(cropRect.width, cropRect.height);
        final painter = tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint &&
                    w.painter.runtimeType.toString() == '_CropOverlayPainter',
              ),
            )
            .painter!;
        final mask = (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
          return result;
        }))!;
        int alpha(double x, double y) =>
            mask[(((cropRect.top + cropRect.height * y).floor() *
                            size.width.toInt() +
                        (cropRect.left + cropRect.width * x).floor()) *
                    4) +
                3];
        expect(
          alpha(.03, .03),
          greaterThan(100),
          reason: 'Square corners are masked.',
        );
        expect(
          alpha(.15, .06),
          0,
          reason: 'Mask follows the gentler 20% profile radius.',
        );
        expect(alpha(.85, .94), 0);
        expect(alpha(.97, .97), greaterThan(100));
        // Zoom/pan remain controlled by the existing interactive crop viewport.
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.minScale, 1);
        expect(viewer.maxScale, 4);
        viewer.transformationController!.value = Matrix4.identity()
          ..scaleByDouble(1.5, 1.5, 1, 1);
        await tester.pump();
        await tester.tap(find.text('confirm'));
        for (var i = 0; i < 100 && saved == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(saved, isNotNull);
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(saved!);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, 1440);
          expect(image.height, 1440);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final output = data!.buffer.asUint8List();
          for (final pixel in [0, 1439, 1440 * 1439, 1440 * 1440 - 1]) {
            expect(output.sublist(pixel * 4, pixel * 4 + 4), [
              255,
              255,
              255,
              255,
            ], reason: 'Rounded preview is not baked into the uploaded file.');
          }
          image.dispose();
          codec.dispose();
        });
        await tester.pumpAndSettle();
        expect(find.byType(ProfilePhotoCropPage), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
