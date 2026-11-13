import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('measure primary header font ink against the layout center', () async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    for (final label in [
      'чатикс',
      'Чатикс',
      'друзья',
      'Friends',
      'соединение',
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: AppTextStyles.titleLargeFlex.copyWith(color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        painter.width.ceil(),
        painter.height.ceil(),
      );
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var top = image.height, bottom = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (pixels.getUint8((y * image.width + x) * 4 + 3) > 127) {
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      // Diagnostic only: fonts have different visible ascenders/descenders.
      debugPrint(
        'HEADER_INK $label height=${painter.height} top=$top bottom=$bottom delta=${(top + bottom + 1 - painter.height) / 2}',
      );
      image.dispose();
      picture.dispose();
      painter.dispose();
    }
  });
}
