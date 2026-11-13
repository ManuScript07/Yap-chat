import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/widgets/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  for (final choice in ['confirm', 'cancel', 'barrier']) {
    testWidgets('shared confirmation retains its default contract: $choice', (
      tester,
    ) async {
      final context = await _mount(tester, 'en', const Size(390, 844), 1);
      final result = showConfirmationDialog(
        context,
        title: 'Confirm action',
        content: 'Existing two-button confirmation',
        confirmLabel: 'Confirm',
        cancelLabel: 'Cancel',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        false,
      );
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!
          .textStyle!
          .resolve({})!;
      expect(style.fontSize, 15);
      expect(style.fontWeight, FontWeight.w600);
      if (choice == 'barrier') {
        await tester.tapAt(const Offset(10, 10));
      } else {
        await tester.tap(find.text(choice == 'confirm' ? 'Confirm' : 'Cancel'));
      }
      await tester.pumpAndSettle();
      expect(await result, switch (choice) {
        'confirm' => true,
        'cancel' => false,
        _ => null,
      });
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ru', 'en']) {
    for (final size in [const Size(320, 720), const Size(780, 390)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$language limit dialog fits $size at ${scale}x text', (
          tester,
        ) async {
          final context = await _mount(tester, language, size, scale);
          final l10n = AppLocalizations.of(context)!;
          final dismissed = showChatLimitReachedDialog(context, limit: 100);
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text(l10n.chatsLimitTitle), findsOneWidget);
          expect(find.text(l10n.chatsLimitContent(100)), findsOneWidget);
          expect(find.text(l10n.chatsLimitDismiss), findsOneWidget);
          expect(find.byType(TextButton), findsNothing);
          expect(
            tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
            true,
          );
          final buttonStyle = tester
              .widget<FilledButton>(find.byType(FilledButton))
              .style!
              .textStyle!
              .resolve({})!;
          expect(buttonStyle.fontSize, 15);
          expect(buttonStyle.fontWeight, FontWeight.w600);
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(AlertDialog)),
            ).scale(16),
            16 * scale,
          );
          expect(tester.takeException(), isNull);

          // RenderFlex diagnostics alone do not detect clipped paragraph text.
          final paragraphs = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(RichText),
          );
          for (final element in paragraphs.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.size.height,
              greaterThanOrEqualTo(
                paragraph.getMinIntrinsicHeight(paragraph.size.width) - .01,
              ),
              reason: 'Dialog text must remain readable at $scale text scale',
            );
          }
          final dismiss = find.widgetWithText(
            FilledButton,
            l10n.chatsLimitDismiss,
          );
          await tester.ensureVisible(dismiss);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(dismiss);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
          expect(bounds.bottom, lessThanOrEqualTo(size.height));
          await tester.tap(dismiss);
          await tester.pumpAndSettle();
          await dismissed;
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      '$language coalesces concurrent refusals and reopens after dismiss',
      (tester) async {
        final context = await _mount(tester, language, const Size(390, 844), 1);
        final l10n = AppLocalizations.of(context)!;
        final first = showChatLimitReachedDialog(context, limit: 100);
        for (var repeat = 0; repeat < 5; repeat++) {
          expect(
            identical(first, showChatLimitReachedDialog(context, limit: 100)),
            isTrue,
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          identical(first, showChatLimitReachedDialog(context, limit: 100)),
          isTrue,
        );
        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        await first;
        expect(find.byType(AlertDialog), findsNothing);

        final reopened = showChatLimitReachedDialog(context, limit: 100);
        expect(identical(first, reopened), isFalse);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        await reopened;
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$language dialog above a sheet preserves its content and route',
      (tester) async {
        final context = await _mount(tester, language, const Size(390, 844), 1);
        final l10n = AppLocalizations.of(context)!;
        final draft = TextEditingController(
          text: 'retained attachment caption',
        );
        addTearDown(draft.dispose);
        late BuildContext sheetContext;
        var sheetClosed = false;
        final sheet = showModalBottomSheet<void>(
          context: context,
          builder: (context) {
            sheetContext = context;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: TextField(controller: draft),
            );
          },
        );
        unawaited(sheet.then((_) => sheetClosed = true));
        await tester.pumpAndSettle();
        final sheetRoute = ModalRoute.of(sheetContext)!;

        // A ChatBloc listener uses the page context underneath the modal sheet.
        final dialog = showChatLimitReachedDialog(context, limit: 100);
        expect(
          identical(
            dialog,
            showChatLimitReachedDialog(sheetContext, limit: 100),
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(sheetRoute.isActive, isTrue);
        expect(sheetRoute.isCurrent, isFalse);
        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        await dialog;
        expect(sheetClosed, isFalse);
        expect(sheetRoute.isCurrent, isTrue);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(draft.text, 'retained attachment caption');

        final retry = showChatLimitReachedDialog(sheetContext, limit: 100);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        await retry;
        expect(sheetRoute.isCurrent, isTrue);
        expect(draft.text, 'retained attachment caption');
        Navigator.of(sheetContext).pop();
        await tester.pumpAndSettle();
        await sheet;
        expect(sheetClosed, isTrue);
        expect(find.text('underlying page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<BuildContext> _mount(
  WidgetTester tester,
  String language,
  Size size,
  double scale,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      // A bundled font avoids Google Fonts networking and measures real glyphs.
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          pageContext = context;
          return const Scaffold(body: Text('underlying page'));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return pageContext;
}
