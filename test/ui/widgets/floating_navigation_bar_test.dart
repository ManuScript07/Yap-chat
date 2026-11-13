import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/ui.dart';

const _labelsRu = ['чатикс', 'рядом', 'реки', 'друны', 'акк'];
const _labelsEn = ['Chats', 'Nearby', 'Feed', 'Friends', 'Profile'];

List<FloatingNavigationBarItem> _items(bool english) {
  final labels = english ? _labelsEn : _labelsRu;
  const icons = [
    Icons.sms_outlined,
    Icons.place_outlined,
    Icons.auto_awesome_outlined,
    Icons.mood_outlined,
    Icons.person_outline,
  ];
  return [
    for (var i = 0; i < 5; i++)
      FloatingNavigationBarItem(
        icon: icons[i],
        activeIcon: icons[i],
        label: labels[i],
        unreadCount: i == 0
            ? 123
            : i == 3
            ? 8
            : 0,
      ),
  ];
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  for (final size in [
    const Size(280, 640),
    const Size(320, 720),
    const Size(360, 780),
    const Size(780, 360),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final bottom in [0.0, 15.0, 48.0]) {
        for (final english in [false, true]) {
          testWidgets(
            'five tabs fit $size scale=$scale bottom=$bottom en=$english',
            (tester) async {
              final taps = <int>[];
              final media = MediaQueryData(
                size: size,
                padding: EdgeInsets.only(bottom: bottom),
                viewPadding: EdgeInsets.only(
                  bottom: bottom,
                  right: size.width > size.height ? 48 : 0,
                ),
                textScaler: TextScaler.linear(scale),
              );
              final key = GlobalKey();
              await _mount(
                tester,
                media,
                key: key,
                english: english,
                onTap: taps.add,
              );
              final bar = tester.getRect(
                find.byKey(const ValueKey('navigation_surface')),
              );
              final search = tester.getRect(
                find.byKey(const ValueKey('nav_search_reference')),
              );
              expect(
                bar.height,
                closeTo(FloatingNavigationGeometry.heightFor(media), .01),
              );
              expect(
                size.height - bar.bottom,
                closeTo((size.width > size.height ? 0 : bottom) + 10, .01),
              );
              expect(bar.top - search.bottom, closeTo(16, .01));
              expect(bar.left, greaterThanOrEqualTo(0));
              expect(
                bar.right,
                lessThanOrEqualTo(
                  size.width - (size.width > size.height ? 48 : 0),
                ),
              );
              expect(
                find.byKey(const ValueKey('navigation_destination_4')),
                findsOneWidget,
              );
              await tester.tap(
                find.byKey(const ValueKey('navigation_destination_2')),
              );
              await tester.pumpAndSettle();
              expect(taps, [2]);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }

  testWidgets(
    'selection glow rises then fades, rapid taps settle without permanent tickers',
    (tester) async {
      final key = GlobalKey();
      final media = const MediaQueryData(size: Size(360, 780));
      final taps = <int>[];
      await _mount(tester, media, key: key, onTap: taps.add);
      final destination = find.byKey(
        const ValueKey('navigation_destination_2'),
      );
      final point = tester.getRect(destination).centerLeft + const Offset(5, 0);
      final before = await _brightness(tester, key, point);
      await tester.tap(destination);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final peak = await _brightness(tester, key, point);
      await tester.pump(const Duration(milliseconds: 1600));
      final tail = await _brightness(tester, key, point);
      expect(peak, greaterThan(before + 6));
      expect(peak, greaterThan(tail + 6));
      expect(tail, greaterThan(before + 8));
      for (final i in [4, 1, 3, 0, 2, 2]) {
        await tester.tap(find.byKey(ValueKey('navigation_destination_$i')));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(taps, [2, 4, 1, 3, 0, 2, 2]);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('selection halo crosses the tab boundary without a hard edge', (
    tester,
  ) async {
    final key = GlobalKey();
    await _mount(tester, const MediaQueryData(size: Size(360, 400)), key: key);
    final tab = find.byKey(const ValueKey('navigation_destination_2'));
    final rect = tester.getRect(tab);
    // Above the icon: only the halo, not glyphs or badge pixels.
    final inside = Offset(rect.right - 2, rect.top + 6);
    final outside = Offset(rect.right + 2, rect.top + 6);
    final before = await _brightness(tester, key, outside);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final inner = await _brightness(tester, key, inside);
    final outer = await _brightness(tester, key, outside);
    expect(outer, greaterThan(before + 5));
    expect((inner - outer).abs(), lessThan(4));
    await _capture(tester, key, 'tmp/bottom_navigation_halo_peak.png');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rim has a clear top highlight and subdued lower edge', (
    tester,
  ) async {
    final key = GlobalKey();
    await _mount(tester, const MediaQueryData(size: Size(360, 400)), key: key);
    final bar = tester.getRect(
      find.byKey(const ValueKey('navigation_surface')),
    );
    final top = await _brightness(tester, key, Offset(bar.center.dx, bar.top));
    final bottom = await _brightness(
      tester,
      key,
      Offset(bar.center.dx, bar.bottom - 1),
    );
    expect(top, greaterThan(bottom + 35));
    expect(top, lessThan(85));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('halo expands symmetrically above and below the tab center', (
    tester,
  ) async {
    final key = GlobalKey();
    await _mount(tester, const MediaQueryData(size: Size(360, 400)), key: key);
    final tab = find.byKey(const ValueKey('navigation_destination_2'));
    final rect = tester.getRect(tab);
    // Outside the icon/label bounds. Subtract the fixed glass background,
    // whose upper and lower tints intentionally differ.
    final top = Offset(rect.right + 3, rect.top + 6);
    final bottom = Offset(rect.right + 3, rect.bottom - 7);
    final beforeTop = await _brightness(tester, key, top);
    final beforeBottom = await _brightness(tester, key, bottom);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final topGain = await _brightness(tester, key, top) - beforeTop;
    final bottomGain = await _brightness(tester, key, bottom) - beforeBottom;
    expect(topGain, greaterThan(10));
    expect(bottomGain, greaterThan(10));
    expect((topGain - bottomGain).abs(), lessThanOrEqualTo(2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('halo rises gradually and repeated taps do not flash darker', (
    tester,
  ) async {
    final key = GlobalKey();
    await _mount(tester, const MediaQueryData(size: Size(360, 400)), key: key);
    final tab = find.byKey(const ValueKey('navigation_destination_2'));
    final point = tester.getRect(tab).centerLeft + const Offset(5, 0);
    final before = await _brightness(tester, key, point);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final early = await _brightness(tester, key, point);
    await tester.pump(const Duration(milliseconds: 100));
    final middle = await _brightness(tester, key, point);
    await tester.pump(const Duration(milliseconds: 200));
    final peak = await _brightness(tester, key, point);
    expect(early, greaterThan(before));
    expect(middle, greaterThan(early + 3));
    expect(peak, greaterThan(middle + 3));
    await tester.tap(tab);
    await tester.pump();
    final repeated = await _brightness(tester, key, point);
    expect((repeated - peak).abs(), lessThanOrEqualTo(1));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('accessibility tap selects the same destination exactly once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final taps = <int>[];
    await _mount(
      tester,
      const MediaQueryData(size: Size(360, 780)),
      key: GlobalKey(),
      onTap: taps.add,
    );
    final node = tester.getSemantics(
      find.byKey(const ValueKey('navigation_destination_2')),
    );
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(taps, [2]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('reduced motion has no selection pulse ticker', (tester) async {
    final key = GlobalKey();
    await _mount(
      tester,
      const MediaQueryData(size: Size(360, 780), disableAnimations: true),
      key: key,
    );
    await tester.tap(find.byKey(const ValueKey('navigation_destination_4')));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final ambient in [false, true]) {
    testWidgets(
      'render rounded rim against dark and ambient backgrounds ambient=$ambient',
      (tester) async {
        final key = GlobalKey();
        await _mount(
          tester,
          const MediaQueryData(size: Size(360, 400)),
          key: key,
          ambient: ambient,
        );
        await _capture(
          tester,
          key,
          'tmp/bottom_navigation_${ambient ? 'glow' : 'dark'}.png',
        );
        final bar = tester.getRect(
          find.byKey(const ValueKey('navigation_surface')),
        );
        expect(bar.width, 308);
        expect(bar.height, 64);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  MediaQueryData media, {
  required GlobalKey key,
  bool english = false,
  bool ambient = false,
  ValueChanged<int>? onTap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = media.size;
  addTearDown(tester.view.reset);
  var selected = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff03a6e1),
          onSurface: Color(0xfff9f9f9),
          outline: Color(0xff6e7586),
        ),
      ),
      home: MediaQuery(
        data: media,
        child: RepaintBoundary(
          key: key,
          child: Material(
            color: Colors.black,
            child: StatefulBuilder(
              builder: (context, setState) => Stack(
                children: [
                  if (ambient)
                    const Positioned.fill(child: BottomAmbientGlow()),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom:
                        FloatingNavigationGeometry.occupiedHeight(media) + 16,
                    child: Container(
                      key: const ValueKey('nav_search_reference'),
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FloatingNavigationBar(
                      activeIndex: selected,
                      onTap: (i) {
                        onTap?.call(i);
                        setState(() => selected = i);
                      },
                      items: _items(english),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<double> _brightness(
  WidgetTester tester,
  GlobalKey key,
  Offset point,
) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final origin = boundary.localToGlobal(Offset.zero);
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final x = (point.dx - origin.dx).round(),
        y = (point.dy - origin.dy).round();
    final index = (y * image.width + x) * 4;
    final result =
        (data.getUint8(index) +
            data.getUint8(index + 1) +
            data.getUint8(index + 2)) /
        3;
    image.dispose();
    return result;
  }))!;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File(path).writeAsBytes(png.buffer.asUint8List());
    image.dispose();
  });
}
