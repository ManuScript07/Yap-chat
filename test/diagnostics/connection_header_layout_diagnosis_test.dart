// Layout feasibility study using existing widgets and bundled fonts.
// The fitted connection title below is a test candidate, not production UI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

final _measurements = <Map<String, Object?>>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['RobotoFlex', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
  });
  tearDownAll(
    () => File('tmp/connection_header_layout_diagnosis.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_measurements),
    ),
  );
  for (final locale in ['ru', 'en']) {
    for (final size in [
      const Size(320, 720),
      const Size(360, 800),
      const Size(780, 390),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('connection title fits $locale $size scale=$scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final label = locale == 'ru' ? 'соединение…' : 'connecting…';
          final ordinary = locale == 'ru' ? 'чатикс' : 'chatix';
          final state = ValueNotifier(false);
          addTearDown(state.dispose);
          var taps = 0;
          await tester.pumpWidget(
            _app(
              locale,
              scale,
              ValueListenableBuilder<bool>(
                valueListenable: state,
                builder: (context, connecting, _) => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 130,
                    child: PrimaryAppBar(
                      title: ordinary,
                      actionIcon: Icons.add_comment_rounded,
                      onActionPressed: () => taps++,
                      titleWidget: SizedBox(
                        height: 52 * scale,
                        child: AnimatedStatusSwitcher(
                          alignment: AlignmentDirectional.centerStart,
                          scaleAlignment: AlignmentDirectional.centerStart,
                          scaleBegin: .94,
                          child: connecting
                              ? FittedBox(
                                  key: const ValueKey('connecting-fit'),
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    label,
                                    style: AppTextStyles.titleLargeFlex,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                )
                              : Align(
                                  key: const ValueKey('ordinary'),
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    ordinary,
                                    style: AppTextStyles.titleLargeFlex,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final action = find.byType(IconButton);
          final beforeAction = tester.getRect(action);
          final beforeHeader = tester.getRect(find.byType(PrimaryAppBar));
          final landscape = size.width > size.height;
          final available = size.width - 32 - 42 - (landscape ? 40 : 0);
          final raw = TextPainter(
            text: TextSpan(text: label, style: AppTextStyles.titleLargeFlex),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
          final rawWidth = raw.width;
          raw.dispose();
          state.value = true;
          await tester.pump();
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 30));
            final rect = tester.getRect(find.text(label));
            expect(rect.left, closeTo(16 + (landscape ? 28 : 0), .01));
            expect(rect.right, lessThanOrEqualTo(beforeAction.left + .01));
            expect(tester.getRect(action), beforeAction);
            expect(tester.getRect(find.byType(PrimaryAppBar)), beforeHeader);
            expect(tester.takeException(), isNull);
          }
          await tester.tap(action);
          expect(taps, 1);
          final fitted = tester.getRect(find.text(label));
          _measurements.add({
            'locale': locale,
            'width': size.width,
            'height': size.height,
            'scale': scale,
            'raw_title_width': rawWidth,
            'available_title_width': available,
            'needs_fit': rawWidth > available,
            'fitted_width': fitted.width,
            'fitted_height': fitted.height,
          });
          // Interruption/reversal must preserve action geometry and start edge.
          for (final value in [false, true, false]) {
            state.value = value;
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 45));
            expect(tester.getRect(action), beforeAction);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets(
    'existing chat status keeps online color and exposes bounded label width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _app(
          'ru',
          2,
          const Align(
            alignment: Alignment.topCenter,
            child: ChatAppBar(
              userName: 'Очень длинное имя собеседника',
              isOnline: true,
            ),
          ),
        ),
      );
      final label = tester.widget<Text>(find.text('в сети'));
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.text('в сети'),
          matching: find.byType(RichText),
        ),
      );
      final effectiveStyle = (richText.text as TextSpan).style!;
      expect(label.style!.color, AppColors.incomingBubble);
      expect(label.style!.fontWeight, FontWeight.w600);
      expect(label.style!.fontSize, 14);
      final width = tester
          .getSize(
            find.ancestor(
              of: find.text('в сети'),
              matching: find.byType(AnimatedStatusSwitcher),
            ),
          )
          .width;
      for (final text in ['соединение…', 'connecting…']) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(2),
        )..layout();
        _measurements.add({
          'kind': 'chat-status',
          'label': text,
          'raw_width': painter.width,
          'available_width': width,
          'font_family': effectiveStyle.fontFamily,
        });
        painter.dispose();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Widget _app(String locale, double scale, Widget child) => MaterialApp(
  theme: ThemeData.dark().copyWith(
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brandPrimary,
      onPrimary: AppColors.onBrandPrimary,
      surface: AppColors.surfaceOverlay,
      onSurface: AppColors.textPrimary,
    ),
  ),
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      padding:
          MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height
          ? const EdgeInsets.only(left: 28, right: 12)
          : const EdgeInsets.only(top: 24),
    ),
    child: child!,
  ),
  home: Scaffold(body: child),
);
