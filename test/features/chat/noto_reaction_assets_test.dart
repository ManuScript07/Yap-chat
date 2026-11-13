import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/bundled_asset_licenses.dart';
import 'package:yap_chat/features/chat/data/models/message_reaction.dart';
import 'package:yap_chat/features/chat/widgets/message_reactions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Noto artwork and its license are bundled for offline use', () async {
    for (final code in ReactionCode.values) {
      final svg = await rootBundle.loadString(code.assetPath);
      expect(svg, contains('viewBox="0 0 128 128"'));
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('<script')));
    }
    final notice = await rootBundle.loadString('assets/reactions/NOTICE');
    expect(notice, contains('e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e'));
    for (final code in ReactionCode.values) {
      expect(notice, contains('${code.wireName}.svg <- 2D/svg/emoji_u'));
    }
  });

  test('Noto license is registered once with the original copyright', () async {
    registerBundledAssetLicenses();
    registerBundledAssetLicenses();
    final entries = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('Noto Emoji'))
        .toList();
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Copyright 2013 Google, Inc.'));
    expect(text, contains('TERMS AND CONDITIONS FOR USE, REPRODUCTION'));
  });

  testWidgets('all six emoji rasterize at pill and picker sizes', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final icons = <GlobalKey>[];
    await tester.binding.setSurfaceSize(const Size(480, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final background in [
                    Colors.white,
                    const Color(0xFF141414),
                  ])
                    ColoredBox(
                      color: background,
                      child: Column(
                        children: [
                          for (final size in [24.0, 32.0, 64.0])
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final code in ReactionCode.values)
                                  SizedBox(
                                    width: 76,
                                    height: 76,
                                    child: Center(
                                      child: ReactionIcon(
                                        code,
                                        size: size,
                                        key: () {
                                          final key = GlobalKey();
                                          icons.add(key);
                                          return key;
                                        }(),
                                      ),
                                    ),
                                  ),
                              ],
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
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final origin = boundary.localToGlobal(Offset.zero);
    final rects = icons.map((key) {
      final box = key.currentContext!.findRenderObject() as RenderBox;
      return (box.localToGlobal(Offset.zero) - origin) & box.size;
    }).toList();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        // Check actual pixels, not merely successful SVG parsing: every icon
        // must be colored on both backgrounds, including at 24 logical pixels.
        for (final rect in rects) {
          var coloredPixels = 0;
          for (var y = (rect.top * 2).ceil(); y < rect.bottom * 2; y++) {
            for (var x = (rect.left * 2).ceil(); x < rect.right * 2; x++) {
              final offset = (y * image.width + x) * 4;
              final r = data.getUint8(offset);
              final g = data.getUint8(offset + 1);
              final b = data.getUint8(offset + 2);
              if ((r - g).abs() > 20 || (g - b).abs() > 20) coloredPixels++;
            }
          }
          expect(coloredPixels, greaterThan(100));
        }
        if (const bool.fromEnvironment('WRITE_NOTO_PREVIEW')) {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File('output/noto-reactions-preview.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png.buffer.asUint8List());
        }
      } finally {
        image.dispose();
      }
    });
  });
}
