import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
      'local frames are bounded and release listeners cancel=$cancel',
      (tester) async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        final files = [
          for (var i = 0; i < 20; i++)
            File(
              'assets/logo/logo_yap_chat.png',
            ).copySync('tmp/avatar_frame_lease_${cancel}_$i.png'),
        ];
        addTearDown(() {
          for (final file in files) {
            file.deleteSync();
          }
        });
        late BuildContext host;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                host = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        var current = true;
        final lease = (await tester.runAsync(() async {
          final pending = LocalAvatarFrames.prepare(
            host,
            files.map((f) => f.absolute.path),
            isCurrent: () => current,
            budget: const Duration(seconds: 2),
          );
          if (cancel) current = false;
          return pending;
        }))!;
        expect(
          PaintingBinding.instance.imageCache.liveImageCount,
          cancel ? 0 : 12,
        );
        lease.dispose();
        await tester.pump();
        expect(PaintingBinding.instance.imageCache.liveImageCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('missing and corrupt local files do not stall or leak', (
    tester,
  ) async {
    final corrupt = File('tmp/corrupt_avatar_frame_lease.png')
      ..writeAsStringSync('not an image');
    addTearDown(corrupt.deleteSync);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final lease = (await tester.runAsync(
      () => LocalAvatarFrames.prepare(host, [
        'tmp/missing_avatar_frame_lease.png',
        corrupt.absolute.path,
      ], isCurrent: () => true),
    ))!;
    lease.dispose();
    await tester.pump();
    expect(PaintingBinding.instance.imageCache.liveImageCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
