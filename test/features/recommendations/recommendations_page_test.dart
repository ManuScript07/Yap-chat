import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/recommendations.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets(
    'long text expands inline without starting another feed request',
    (tester) async {
      final feed = _Feed();
      final text = List.filled(14, 'long text with emoji 🚀').join('\n');
      feed.next = Future.value(
        FeedPageResult(
          posts: [
            FeedPost(
              id: 'long-post',
              authorId: 'author',
              authorName: 'author',
              text: text,
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await _mount(tester, feed);
      final collapsed = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan?.toPlainText().endsWith('more…') ?? false),
      );
      expect(collapsed, findsOneWidget);
      await tester.tap(collapsed);
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(collapsed, findsNothing);
      expect(feed.calls, [FeedTab.forYou]);
    },
  );
  testWidgets('loads only visited tabs and restores the scroll offset', (
    tester,
  ) async {
    final feed = _Feed();
    await _mount(tester, feed);
    expect(feed.calls, [FeedTab.forYou]);
    expect(find.byType(ConnectionStatusTitle), findsOneWidget);
    expect(find.text('feed'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('inbox')), const Size(42, 42));
    expect(find.byTooltip('new post'), findsOneWidget);
    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    final offset = tester.widget<CustomScrollView>(list).controller!.offset;
    expect(offset, greaterThan(100));

    await tester.tap(find.text('friends'));
    await tester.pumpAndSettle();
    expect(feed.calls, [FeedTab.forYou, FeedTab.friends]);
    expect(tester.widget<CustomScrollView>(list).controller!.offset, 0);

    await tester.tap(find.text('for you'));
    await tester.pumpAndSettle();
    expect(tester.widget<CustomScrollView>(list).controller!.offset, offset);
    expect(feed.calls, [FeedTab.forYou, FeedTab.friends]);
    await tester.tap(find.byTooltip('inbox'));
    await tester.pumpAndSettle();
    expect(find.text('coming soon'), findsOneWidget);
  });

  testWidgets('the list scrolls under fixed tabs and the header', (
    tester,
  ) async {
    await _mount(tester, _Feed());
    final list = find.byType(CustomScrollView);
    final tabs = find.byType(PrimarySegmentedControl);
    final firstCard = find.ancestor(
      of: find.text('forYou post 0'),
      matching: find.byType(Card),
    );
    final tabsRect = tester.getRect(tabs);
    expect(
      find.ancestor(of: tabs, matching: find.byType(PinnedHeaderSliver)),
      findsOneWidget,
    );
    expect(tabsRect.top, PrimaryHeaderGeometry.compactTabsTop);
    expect(tester.getTopLeft(list).dy, lessThan(tabsRect.top));
    expect(tester.getTopLeft(firstCard).dy, greaterThan(tabsRect.bottom));
    tester.widget<CustomScrollView>(list).controller!.jumpTo(70);
    await tester.pump();
    expect(tester.getRect(tabs), tabsRect);
    expect(tester.getTopLeft(firstCard).dy, lessThan(tabsRect.top));
  });

  testWidgets('refresh emits one haptic and keeps cards while waiting', (
    tester,
  ) async {
    final feed = _Feed();
    await _mount(tester, feed);
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    // Respect the short cooldown between opening the feed and refreshing it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    final pending = Completer<FeedPageResult>();
    feed.next = pending.future;
    final firstCard = find.ancestor(
      of: find.text('forYou post 0'),
      matching: find.byType(Card),
    );
    final restTop = tester.getTopLeft(firstCard).dy;
    final tabs = find.byType(PrimarySegmentedControl);
    final tabsTop = tester.getTopLeft(tabs).dy;
    final gesture = await tester.startGesture(const Offset(200, 280));
    await gesture.moveBy(const Offset(0, 42));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 32));
    await tester.pump();
    expect(tester.getTopLeft(firstCard).dy, greaterThan(restTop));
    expect(tester.getTopLeft(tabs).dy, closeTo(tabsTop, .01));
    expect(feed.calls, [FeedTab.forYou]);
    await gesture.moveBy(const Offset(0, 340));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate'),
      hasLength(1),
    );
    expect(feed.calls, [FeedTab.forYou, FeedTab.forYou]);
    expect(find.text('forYou post 0'), findsOneWidget);
    expect(tester.getTopLeft(firstCard).dy, greaterThan(restTop + 40));
    pending.complete(const FeedPageResult(posts: []));
    await tester.pumpAndSettle();
    expect(find.text('no posts yet'), findsOneWidget);
  });

  testWidgets(
    'account replacement clears old posts while the new account loads',
    (tester) async {
      final feed = _Feed();
      final accounts = await _mount(tester, feed);
      expect(find.text('forYou post 0'), findsOneWidget);
      final pending = Completer<FeedPageResult>();
      feed.next = pending.future;
      accounts.setAuthenticatedUser('new-viewer');
      await tester.pump();
      await tester.pump();
      expect(find.text('forYou post 0'), findsNothing);
      expect(feed.calls, [FeedTab.forYou, FeedTab.forYou]);
      pending.complete(const FeedPageResult(posts: []));
      await tester.pumpAndSettle();
      expect(find.text('no posts yet'), findsOneWidget);
    },
  );
}

Future<AccountSessionController> _mount(WidgetTester tester, _Feed feed) async {
  final accounts = AccountSessionController(initialUserId: 'viewer');
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AccountSessionController>.value(value: accounts),
        RepositoryProvider<IFeedRepository>.value(value: feed),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RecommendationsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return accounts;
}

class _Feed implements IFeedRepository {
  final calls = <FeedTab>[];
  Future<FeedPageResult>? next;

  @override
  Future<FeedPageResult> fetch(
    FeedTab tab, {
    required AccountSessionSnapshot account,
    FeedCursor? cursor,
  }) async {
    calls.add(tab);
    final pending = next;
    next = null;
    return pending ??
        FeedPageResult(
          posts: [
            for (var i = 0; i < 20; i++)
              FeedPost(
                id: '${tab.name}-$i',
                authorId: 'author',
                authorName: 'Test author',
                text: '${tab.name} post $i',
                createdAt: DateTime.utc(2026, 11, 13),
              ),
          ],
        );
  }

  @override
  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async => throw UnimplementedError();
}
