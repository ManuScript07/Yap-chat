import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final family in ['RobotoFlex', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
  });

  for (final locale in ['ru', 'en']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final geometry in [
        (size: const Size(320, 720), ime: 0.0),
        (size: const Size(360, 800), ime: 300.0),
        (size: const Size(840, 480), ime: 0.0),
        // The header must leave room for empty feedback before the search bar
        // reaches it, including this case where searchBarTop is still > 130.
        (size: const Size(780, 390), ime: 180.0),
        (size: const Size(780, 390), ime: 210.0),
        (size: const Size(1024, 600), ime: 260.0),
      ]) {
        testWidgets(
          'empty/error anchors and retry $locale scale=$scale $geometry',
          (tester) async {
            _setGeometry(tester, geometry.size, geometry.ime);
            final fixture = _Fixture();
            addTearDown(fixture.close);
            await _mount(tester, fixture, locale: locale, scale: scale);
            if (geometry.size == const Size(780, 390) && geometry.ime == 180) {
              // Reserve body space while rows are still present too. The
              // later empty snapshot must not need an outer Bloc rebuild.
              expect(find.byType(PrimaryAppBar), findsNothing);
              expect(find.byKey(const ValueKey('cached')), findsOneWidget);
            }
            await tester.enterText(find.byType(TextField), 'missing');
            await _pump(tester);
            expect(fixture.repository.queries, ['missing']);
            await _publish(tester, fixture);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ChatsPage)),
            )!;
            final label = find.byKey(const ValueKey('chats_empty_label'));
            final retry = find.widgetWithText(FilledButton, l10n.repeat);
            expect(find.text(l10n.chatsNoSearchResults), findsOneWidget);
            expect(retry, findsNothing);
            _expectLabel(tester, label);
            final anchor = tester.getTopLeft(label);
            final scroll = tester.state<ScrollableState>(
              find.descendant(
                of: find.byKey(const ValueKey('chats_empty_scroll')),
                matching: find.byType(Scrollable),
              ),
            );
            expect(scroll.position.pixels, 0);
            expect(fixture.repository.requests, isEmpty);

            await _publish(
              tester,
              fixture,
              pageError: const FormatException('bad local page'),
            );
            expect(fixture.bloc.state.status, ChatsStatus.failure);
            expect(find.text(l10n.failedToLoadChats), findsOneWidget);
            expect(l10n.failedToLoadChats.endsWith('.'), isFalse);
            _expectLabel(tester, label);
            expect(tester.getTopLeft(label).dy, closeTo(anchor.dy, .01));
            final errorRect = tester.getRect(label);
            await _expectRetry(tester, retry, l10n.repeat);
            expect(fixture.repository.requests, isEmpty);

            // A busy retry uses the same reserved action slot as the button.
            await _publish(
              tester,
              fixture,
              pageError: const FormatException('bad local page'),
              refreshing: true,
            );
            expect(tester.getRect(label), errorRect);
            expect(retry, findsNothing);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            final spinner = find.byType(CircularProgressIndicator);
            expect(tester.getSize(spinner), const Size(36, 36));
            expect(
              tester.widget<CircularProgressIndicator>(spinner).strokeWidth,
              4,
            );
            expect(fixture.repository.requests, isEmpty);

            await _publish(
              tester,
              fixture,
              pageError: const FormatException('bad local page'),
            );
            expect(tester.getRect(label), errorRect);
            await _expectRetry(tester, retry, l10n.repeat);
            await tester.tap(retry);
            await _pump(tester);
            expect(fixture.repository.requests, [true]);

            await _publish(
              tester,
              fixture,
              refreshError: const SocketException('retained head error'),
            );
            // The real Bloc still reports failure for this repository snapshot;
            // only its presentation changes to accurately describe saved rows.
            expect(fixture.bloc.state.status, ChatsStatus.failure);
            expect(find.text(l10n.failedToLoadChats), findsNothing);
            expect(find.text(l10n.chatsNoSavedSearchResults), findsOneWidget);
            _expectLabel(tester, label);
            final savedRect = tester.getRect(label);
            expect(savedRect.top, closeTo(anchor.dy, .01));
            await _expectRetry(tester, retry, l10n.repeat);
            await _publish(tester, fixture);
            expect(find.text(l10n.chatsNoSearchResults), findsOneWidget);
            expect(retry, findsNothing);
            expect(tester.getTopLeft(label).dy, closeTo(savedRect.top, .01));
            expect(fixture.repository.requests, [true]);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final locale in ['ru', 'en']) {
    for (final landscape in [false, true]) {
      for (final offline in [false, true]) {
        testWidgets('feedback uses the rows layer and closes IME smoothly '
            '$locale landscape=$landscape offline=$offline', (tester) async {
          final size = landscape ? const Size(780, 390) : const Size(360, 800);
          final height = landscape ? 210.0 : 300.0;
          _setGeometry(tester, size, height);
          final fixture = _Fixture();
          addTearDown(fixture.close);
          await _mount(
            tester,
            fixture,
            locale: locale,
            scale: landscape ? 1.5 : 1,
          );
          await tester.enterText(find.byType(TextField), 'missing');
          await _pump(tester);
          await _publish(
            tester,
            fixture,
            refreshError: offline ? const SocketException('offline') : null,
          );
          final label = find.byKey(const ValueKey('chats_empty_label'));
          final scrollView = find.byKey(const ValueKey('chats_empty_scroll'));
          expect(
            tester.widget<SingleChildScrollView>(scrollView).physics,
            offline
                ? isA<ClampingScrollPhysics>()
                : isA<NeverScrollableScrollPhysics>(),
          );
          // Full-page scrolling stays BELOW the same transparent chrome as rows.
          await tester.drag(scrollView, const Offset(0, -140));
          await tester.pumpAndSettle();
          _expectFeedbackLayer(tester);
          final scroll = tester.state<ScrollableState>(
            find.descendant(of: scrollView, matching: find.byType(Scrollable)),
          );
          if (!offline) expect(scroll.position.pixels, 0);
          scroll.position.jumpTo(0);
          await tester.pump();
          var oldSearchTop = tester.getTopLeft(find.byType(GlassSearchBar)).dy;
          var oldLabelTop = tester.getTopLeft(label).dy;
          for (var inset = height - 6; inset >= 0; inset -= 6) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pump(const Duration(milliseconds: 16));
            _expectFeedbackLayer(tester);
            final searchTop = tester.getTopLeft(find.byType(GlassSearchBar)).dy;
            final labelTop = tester.getTopLeft(label).dy;
            expect((searchTop - oldSearchTop).abs(), lessThan(28));
            expect((labelTop - oldLabelTop).abs(), lessThan(24));
            oldSearchTop = searchTop;
            oldLabelTop = labelTop;
            expect(tester.takeException(), isNull);
          }
          // Preserve the original field's motion at 1 -> 0, with feedback
          // following the same curve rather than jumping to the target inset.
          for (final inset in [1.0, 0.0]) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pump(const Duration(milliseconds: 16));
            final searchTop = tester.getTopLeft(find.byType(GlassSearchBar)).dy;
            expect((searchTop - oldSearchTop).abs(), lessThan(28));
            oldSearchTop = searchTop;
            _expectFeedbackLayer(tester);
          }
          await tester.pumpAndSettle();
          _expectFeedbackLayer(tester);
          _expectLabel(tester, label);
          expect(fixture.repository.requests, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final locale in ['ru', 'en']) {
    testWidgets(
      'retry scrolls beneath existing chrome and stays tappable $locale',
      (tester) async {
        _setGeometry(tester, const Size(780, 350), 0);
        final fixture = _Fixture();
        addTearDown(fixture.close);
        await _mount(
          tester,
          fixture,
          locale: locale,
          scale: 2,
          capturePaint: true,
        );
        await tester.enterText(find.byType(TextField), 'missing');
        await _pump(tester);
        await _publish(
          tester,
          fixture,
          refreshError: const SocketException('offline'),
        );
        final scrollFinder = find.byKey(const ValueKey('chats_empty_scroll'));
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: scrollFinder, matching: find.byType(Scrollable)),
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        final label = find.byKey(const ValueKey('chats_empty_label'));
        final header = find.byKey(const ValueKey('chats_header_clip'));
        expect(
          tester.getRect(label).top,
          greaterThanOrEqualTo(tester.getRect(header).bottom),
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        expect(
          tester.getRect(label).top,
          lessThan(tester.getRect(header).bottom),
        );
        // Pixel-level contract: the scrolled text must actually contribute
        // pixels THROUGH the existing header gradient. Coordinates alone
        // would also pass with the former hard clip hiding those glyphs.
        final scene = find.byKey(const ValueKey('feedback_paint_scene'));
        final boundary = tester.renderObject<RenderRepaintBoundary>(scene);
        Future<List<int>> capture() async => (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = List<int>.of(data!.buffer.asUint8List());
          image.dispose();
          return bytes;
        }))!;
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: label, matching: find.byType(RichText)),
        );
        final visibleText = paragraph.text;
        final withText = await capture();
        paragraph.text = TextSpan(
          text: visibleText.toPlainText(),
          style: visibleText.style!.copyWith(color: Colors.transparent),
        );
        await tester.pump();
        final withoutText = await capture();
        paragraph.text = visibleText;
        await tester.pump();
        final sample = tester
            .getRect(label)
            .intersect(tester.getRect(header))
            .shift(-tester.getTopLeft(scene));
        final width = boundary.size.width.ceil();
        expect(
          _changedPixels(withText, withoutText, width, sample),
          greaterThan(50),
          reason:
              'Text is painted beneath the normal gradient, not clipped out.',
        );
        _expectFeedbackLayer(tester);
        expect(
          find.descendant(
            of: find.byType(GlassSearchBar),
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ChatsPage)),
        )!;
        final retry = find.widgetWithText(FilledButton, l10n.repeat);
        // At the start of a cramped page the action extends under the field.
        // Its text must contribute pixels through the REAL BackdropFilter too.
        scroll.position.jumpTo(0);
        await tester.pump();
        final buttonParagraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: retry, matching: find.byType(RichText)),
        );
        final buttonText = buttonParagraph.text;
        final withButtonText = await capture();
        buttonParagraph.text = TextSpan(
          text: buttonText.toPlainText(),
          style: buttonText.style!.copyWith(color: Colors.transparent),
        );
        await tester.pump();
        final withoutButtonText = await capture();
        buttonParagraph.text = buttonText;
        await tester.pump();
        final fieldSample = tester
            .getRect(find.byType(GlassSearchBar))
            .shift(-tester.getTopLeft(scene));
        expect(
          _changedPixels(withButtonText, withoutButtonText, width, fieldSample),
          greaterThan(10),
          reason: 'The action is beneath the existing glass layer.',
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        expect(
          tester.getRect(retry).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(GlassSearchBar)).top - 7.99,
          ),
        );
        await tester.tap(retry);
        await _pump(tester);
        expect(fixture.repository.requests, [true]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'search motion matches the committed AnimatedPositioned contract',
    (tester) async {
      _setGeometry(tester, const Size(360, 800), 0);
      final fixture = _Fixture();
      addTearDown(fixture.close);
      await _mount(tester, fixture, referenceSearchMotion: true);
      Future<void> compareFrames() async {
        await tester.pump();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getTopLeft(find.byType(GlassSearchBar)).dy,
            closeTo(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('baseline_search_reference')),
                  )
                  .dy,
              .01,
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }

      for (final inset in [0.0, 1.0, 60.0, 180.0, 300.0, 140.0, 1.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await compareFrames();
      }
      fixture.bloc.add(const ChatSelectionToggled('cached'));
      await compareFrames();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await compareFrames();
      fixture.bloc.add(const ChatSelectionCleared());
      await compareFrames();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final geometry in [
    (size: const Size(360, 800), ime: 0.0),
    (size: const Size(360, 800), ime: 300.0),
    (size: const Size(840, 480), ime: 0.0),
    (size: const Size(780, 390), ime: 210.0),
  ]) {
    testWidgets('search loading uses the regular indicator $geometry', (
      tester,
    ) async {
      _setGeometry(tester, geometry.size, geometry.ime);
      final fixture = _Fixture();
      addTearDown(fixture.close);
      await _mount(tester, fixture);
      await tester.enterText(find.byType(TextField), 'pending');
      await _pump(tester);
      fixture.bloc.add(
        const ChatsListViewUpdated(
          ChatListViewState(query: 'pending', chats: [], ready: false),
          0,
        ),
      );
      await _pump(tester);
      expect(fixture.bloc.state.status, ChatsStatus.loading);
      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      expect(tester.getSize(spinner), const Size(36, 36));
      expect(tester.widget<CircularProgressIndicator>(spinner).strokeWidth, 4);
      expect(
        tester.getCenter(spinner).dx,
        closeTo(geometry.size.width / 2, .01),
      );
      expect(
        tester.getRect(spinner).bottom,
        lessThan(tester.getRect(find.byType(GlassSearchBar)).top),
      );
      expect(fixture.repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scenario in [
    (
      name: 'transport refresh only',
      page: null,
      refresh: const SocketException('offline'),
      saved: true,
    ),
    (
      name: 'service refresh only',
      page: null,
      refresh: const PostgrestException(message: 'unavailable', code: '503'),
      saved: true,
    ),
    (
      name: 'timeout refresh only',
      page: null,
      refresh: TimeoutException('head timeout'),
      saved: true,
    ),
    (
      name: 'data page plus network refresh',
      page: const FormatException('bad page'),
      refresh: const SocketException('offline'),
      saved: false,
    ),
    (
      name: 'network page plus data refresh',
      page: const SocketException('page offline'),
      refresh: const FormatException('bad refresh'),
      saved: false,
    ),
    (
      name: 'both network errors include real continuation failure',
      page: const SocketException('page offline'),
      refresh: TimeoutException('head timeout'),
      saved: false,
    ),
    (
      name: 'network page only',
      page: const SocketException('page offline'),
      refresh: null,
      saved: false,
    ),
    (
      name: 'cache page only',
      page: StateError('cache unavailable'),
      refresh: null,
      saved: false,
    ),
    (
      name: 'cache refresh only',
      page: null,
      refresh: StateError('cache unavailable'),
      saved: false,
    ),
    (
      name: 'access refresh only',
      page: null,
      refresh: const PostgrestException(message: 'forbidden', code: '403'),
      saved: false,
    ),
    (
      name: 'rate limit refresh only',
      page: null,
      refresh: const PostgrestException(message: 'limited', code: '429'),
      saved: false,
    ),
  ]) {
    for (final withProvider in [false, true]) {
      for (final hasMoreRemote in [false, true]) {
        testWidgets(
          '${scenario.name} provider=$withProvider remote=$hasMoreRemote',
          (tester) async {
            final fixture = _Fixture();
            addTearDown(fixture.close);
            await _mount(tester, fixture, withProvider: withProvider);
            await tester.enterText(find.byType(TextField), 'missing');
            await _pump(tester);
            await _publish(
              tester,
              fixture,
              pageError: scenario.page,
              refreshError: scenario.refresh,
              hasMoreRemote: hasMoreRemote,
            );
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ChatsPage)),
            )!;
            expect(fixture.bloc.state.status, ChatsStatus.failure);
            expect(
              find.text(l10n.chatsNoSavedSearchResults),
              scenario.saved ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(l10n.failedToLoadChats),
              scenario.saved ? findsNothing : findsOneWidget,
            );
            expect(find.text(l10n.chatsNoSearchResults), findsNothing);
            final retry = find.widgetWithText(FilledButton, l10n.repeat);
            expect(retry.hitTestable(), findsOneWidget);
            expect(fixture.repository.requests, isEmpty);
            await tester.tap(retry);
            await _pump(tester);
            expect(fixture.repository.requests, [true]);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final error in [
    const SocketException('cold offline start'),
    const PostgrestException(message: 'service unavailable', code: '503'),
    const FormatException('bad data'),
  ]) {
    testWidgets('cold empty main list remains recoverable: $error', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      await _mount(tester, fixture, cached: false);
      await _publish(tester, fixture, refreshError: error);
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatsPage)))!;
      expect(find.text(l10n.failedToLoadChats), findsOneWidget);
      expect(find.text(l10n.chatsNoSavedSearchResults), findsNothing);
      expect(find.text(l10n.noChats), findsNothing);
      final retry = find.widgetWithText(FilledButton, l10n.repeat);
      await _expectRetry(tester, retry, l10n.repeat);
      expect(fixture.repository.requests, isEmpty);
      await tester.tap(retry);
      await _pump(tester);
      expect(fixture.repository.requests, [true]);
      await _publish(tester, fixture, rows: [_chat()]);
      expect(find.byKey(const ValueKey('cached')), findsOneWidget);
      expect(retry, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

void _setGeometry(WidgetTester tester, Size size, double ime) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: ime);
  tester.view.viewPadding = size.width > size.height
      ? const FakeViewPadding(left: 28, right: 12, bottom: 20)
      : const FakeViewPadding(top: 24, bottom: 20);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetViewPadding);
}

int _changedPixels(List<int> before, List<int> after, int width, Rect sample) {
  var changed = 0;
  for (var y = sample.top.ceil(); y < sample.bottom.floor(); y++) {
    for (var x = sample.left.ceil(); x < sample.right.floor(); x++) {
      final i = (y * width + x) * 4;
      if ((before[i] - after[i]).abs() > 2 ||
          (before[i + 1] - after[i + 1]).abs() > 2 ||
          (before[i + 2] - after[i + 2]).abs() > 2) {
        changed++;
      }
    }
  }
  return changed;
}

void _expectFeedbackLayer(WidgetTester tester) {
  expect(find.byKey(const ValueKey('chats_feedback_clip')), findsNothing);
  final finder = find.byKey(const ValueKey('chats_empty_scroll'));
  final rect = tester.getRect(finder);
  final media = MediaQuery.of(tester.element(finder));
  expect(rect.top, closeTo(0, .01));
  expect(rect.height, closeTo(media.size.height, .01));
  final search = tester.getRect(find.byType(GlassSearchBar));
  expect(rect.bottom, greaterThan(search.bottom));
  final header = find.byKey(const ValueKey('chats_header_clip'));
  if (header.evaluate().isNotEmpty) {
    expect(rect.top, lessThan(tester.getRect(header).bottom));
  }
  final stackFinder = find
      .ancestor(of: find.byType(GlassSearchBar), matching: find.byType(Stack))
      .first;
  final stack = tester.widget<Stack>(stackFinder);
  expect(
    find.descendant(of: find.byWidget(stack.children.first), matching: finder),
    findsOneWidget,
  );
}

void _expectLabel(WidgetTester tester, Finder label) {
  final text = tester.widget<Text>(label);
  expect(text.style!.fontSize, 22);
  expect(text.style!.fontWeight, FontWeight.w700);
  expect(text.style!.height, 1.2);
  expect(text.maxLines, isNull);
  expect(
    find.ancestor(of: label, matching: find.byType(FittedBox)),
    findsNothing,
  );
  final rect = tester.getRect(label);
  final media = MediaQuery.of(tester.element(label));
  final header = find.byType(PrimaryAppBar);
  final top = header.evaluate().isEmpty
      ? media.padding.top
      : tester.getRect(header).bottom;
  expect(rect.top, greaterThanOrEqualTo(top - .01));
  expect(
    rect.bottom,
    lessThanOrEqualTo(tester.getRect(find.byType(GlassSearchBar)).top - 7.99),
  );
  expect(rect.left, greaterThanOrEqualTo(media.padding.left + 15.99));
  expect(
    rect.width,
    closeTo(media.size.width - media.padding.horizontal - 32, .01),
  );
  expect(
    rect.center.dx,
    closeTo(
      (media.padding.left + media.size.width - media.padding.right) / 2,
      .01,
    ),
  );
  expect(
    rect.right,
    lessThanOrEqualTo(media.size.width - media.padding.right - 15.99),
  );
}

Future<void> _expectRetry(
  WidgetTester tester,
  Finder retry,
  String text,
) async {
  final label = find.byKey(const ValueKey('chats_empty_label'));
  // The action is BELOW the full-width label even in short landscape. When
  // they cannot both fit, it remains reachable by scrolling the same column.
  expect(
    tester.getRect(retry).top,
    greaterThanOrEqualTo(tester.getRect(label).bottom + 7.99),
  );
  expect(tester.getCenter(retry).dx, closeTo(tester.getCenter(label).dx, .01));
  await tester.ensureVisible(retry);
  await tester.pumpAndSettle();
  // ensureVisible sees the full viewport (like rows). Reveal the action above
  // the floating field before tapping it, as a user scrolling would do.
  final overflow =
      tester.getRect(retry).bottom -
      tester.getRect(find.byType(GlassSearchBar)).top +
      8;
  if (overflow > .01) {
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('chats_empty_scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(
      (scroll.position.pixels + overflow).clamp(
        scroll.position.minScrollExtent,
        scroll.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }
  expect(retry.hitTestable(), findsOneWidget);
  final rect = tester.getRect(retry);
  final media = MediaQuery.of(tester.element(retry));
  expect(rect.height, greaterThanOrEqualTo(48));
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.left, greaterThanOrEqualTo(media.padding.left));
  expect(rect.right, lessThanOrEqualTo(media.size.width - media.padding.right));
  expect(rect.top, greaterThanOrEqualTo(media.padding.top));
  expect(
    rect.bottom,
    lessThanOrEqualTo(tester.getRect(find.byType(GlassSearchBar)).top - 7.99),
  );
  final buttonLabel = find.descendant(of: retry, matching: find.text(text));
  final labelRect = tester.getRect(buttonLabel);
  expect(rect.contains(labelRect.topLeft), isTrue);
  expect(rect.contains(labelRect.bottomRight - const Offset(.01, .01)), isTrue);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: retry, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  final button = tester.widget<FilledButton>(retry);
  final colors = Theme.of(tester.element(retry)).colorScheme;
  expect(button.style!.backgroundColor!.resolve({}), colors.primary);
  expect(button.style!.foregroundColor!.resolve({}), colors.onPrimary);
  expect(button.style!.shape!.resolve({}), isA<StadiumBorder>());
  expect(button.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w800);
  expect(button.style!.textStyle!.resolve({})!.fontSize, 16);
  expect(button.onPressed, isNotNull);
}

Chat _chat() => Chat(
  id: 'cached',
  peerId: '',
  userName: 'Cached peer',
  lastMessage: 'cached preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _publish(
  WidgetTester tester,
  _Fixture fixture, {
  List<Chat> rows = const [],
  Object? pageError,
  Object? refreshError,
  bool refreshing = false,
  bool hasMoreRemote = false,
}) async {
  fixture.bloc.add(
    ChatsListViewUpdated(
      ChatListViewState(
        query: fixture.bloc.state.searchQuery,
        chats: rows,
        ready: true,
        error: pageError,
        refreshError: refreshError,
        isRefreshing: refreshing,
        hasMoreRemote: hasMoreRemote,
      ),
      0,
    ),
  );
  await _pump(tester);
  final emptyScroll = find.byKey(const ValueKey('chats_empty_scroll'));
  if (emptyScroll.evaluate().isNotEmpty) {
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: emptyScroll, matching: find.byType(Scrollable)),
    );
    scroll.position.jumpTo(0);
    await tester.pump();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String locale = 'ru',
  double scale = 1,
  bool withProvider = true,
  bool cached = true,
  bool referenceSearchMotion = false,
  bool capturePaint = false,
}) async {
  fixture.status.reportNetworkAvailability(false);
  fixture.bloc.add(
    ChatsListViewUpdated(
      ChatListViewState(chats: cached ? [_chat()] : const [], ready: true),
      0,
    ),
  );
  final baseTheme = ThemeData.dark();
  Widget page = referenceSearchMotion
      ? Stack(
          fit: StackFit.expand,
          children: [
            const ChatsPage(),
            const IgnorePointer(child: _BaselineSearchMotion()),
          ],
        )
      : const ChatsPage();
  if (capturePaint) {
    page = RepaintBoundary(
      key: const ValueKey('feedback_paint_scene'),
      child: page,
    );
  }
  Widget app = RepositoryProvider<IChatsRepository>.value(
    value: fixture.repository,
    child: BlocProvider.value(
      value: fixture.bloc,
      child: MaterialApp(
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: 'Roboto'),
          colorScheme: baseTheme.colorScheme.copyWith(
            primary: const Color(0xff006fd6),
            onPrimary: Colors.white,
          ),
        ),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            // These tests settle feedback layout; the repeating connection
            // indicator has a separate animation test.
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  if (withProvider) {
    app = RepositoryProvider<AppConnectionStatus>.value(
      value: fixture.status,
      child: app,
    );
  }
  await tester.pumpWidget(app);
  await _pump(tester);
}

/// Original duration/curve with the updated shared navigation geometry.
class _BaselineSearchMotion extends StatelessWidget {
  const _BaselineSearchMotion();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final selected = context.select<ChatsBloc, bool>(
      (bloc) => bloc.state.isSelectionMode,
    );
    final bottom = keyboard > 0
        ? keyboard + 16
        : FloatingNavigationGeometry.occupiedHeight(media) + 16;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
          left: 0,
          right: 0,
          bottom: selected ? -100 : bottom,
          child: const SizedBox(
            key: ValueKey('baseline_search_reference'),
            height: 50,
          ),
        ),
      ],
    );
  }
}

class _Fixture {
  final repository = _Repository();
  late final bloc = ChatsBloc(chatsRepository: repository);
  final status = AppConnectionStatus(
    accountSessionController: AccountSessionController(initialUserId: 'u'),
    presentationDelay: Duration.zero,
  );

  Future<void> close() async {
    await bloc.close();
    status.dispose();
  }
}

class _Repository implements IChatsRepository, IChatsListRepository {
  final queries = <String>[];
  final requests = <bool>[];

  @override
  Stream<ChatListViewState> watchChatList() => const Stream.empty();
  @override
  Future<void> setChatListQuery(String query) async => queries.add(query);
  @override
  Future<void> loadMoreChatList({bool retry = false}) async =>
      requests.add(retry);
  @override
  void setChatListObservedIds(Set<String> visible, Set<String> selected) {}
  @override
  Future<String?> resolveAvatar(Chat chat) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
