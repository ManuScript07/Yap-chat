import 'dart:async';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/recommendations.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_controls.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets('nearby uses the published location and the shared gate', (
    tester,
  ) async {
    final feed = _Feed();
    final location = _Location();
    await _mount(tester, feed, location: location);
    await tester.tap(find.text('nearby'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationRequiredOverlay), findsOneWidget);
    expect(find.byType(LocationRequiredBackdrop), findsOneWidget);
    expect(location.maxAge, nearbyLocationMaxAge);
    expect(feed.calls, [FeedTab.forYou]);
  });

  testWidgets('expiry blocks a visible nearby tab without a new feed request', (
    tester,
  ) async {
    final feed = _Feed();
    const remaining = Duration(seconds: 30);
    final location = _Location()
      ..publishedAt = DateTime.now().subtract(nearbyLocationMaxAge - remaining);
    await _mount(tester, feed, location: location);
    await tester.tap(find.text('nearby'));
    await tester.pumpAndSettle();
    expect(find.text('nearby post 0'), findsOneWidget);
    expect(find.byType(LocationRequiredOverlay), findsNothing);
    location.publishedAt = null;
    await tester.pump(remaining);
    await tester.pumpAndSettle();
    expect(find.byType(LocationRequiredOverlay), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('nearby post 0'),
        matching: find.byWidgetPredicate(
          (widget) => widget is AbsorbPointer && widget.absorbing,
        ),
      ),
      findsOneWidget,
    );
    expect(feed.calls, [FeedTab.forYou, FeedTab.nearby]);
  });

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
    await tester.drag(list, const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      const Offset(180, 335),
      const Offset(0, 185),
      const Duration(milliseconds: 650),
    );
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
    await tester.timedDragFrom(
      const Offset(180, 335),
      const Offset(0, 185),
      const Duration(milliseconds: 650),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('inbox').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('coming soon'), findsOneWidget);
  });

  testWidgets('the header collapses and floats back on a reverse drag', (
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
    expect(tabsRect.top, PrimaryHeaderGeometry.compactTabsTop);
    expect(tester.getTopLeft(list).dy, lessThan(tabsRect.top));
    expect(tester.getTopLeft(firstCard).dy, greaterThan(tabsRect.bottom));
    final avatar = find.descendant(
      of: firstCard,
      matching: find.byType(FeedPostAuthorAvatar),
    );
    expect(tester.getTopLeft(avatar).dx, 16);
    expect(
      tester.getTopLeft(find.text('forYou post 0')).dx,
      greaterThan(tester.getTopRight(avatar).dx),
    );
    final divider = find.descendant(
      of: firstCard,
      matching: find.byType(Divider),
    );
    expect(tester.getSize(divider).width, 360);
    final controller = tester.widget<CustomScrollView>(list).controller!;
    controller.jumpTo(620);
    await tester.pumpAndSettle();
    expect(find.text('friends').hitTestable(), findsNothing);
    await tester.timedDragFrom(
      const Offset(180, 330),
      const Offset(0, 215),
      const Duration(milliseconds: 650),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    expect(find.text('friends').hitTestable(), findsOneWidget);
  });

  testWidgets('swipe moves the selected segment before making one request', (
    tester,
  ) async {
    final feed = _Feed();
    await _mount(tester, feed);
    final pages =
        tester.widget<PageView>(find.byType(PageView)).controller!
            as SwipeTabController;
    final tabs = find.byType(PrimarySegmentedControl);
    final bar = tester.getRect(tabs);
    final indicator = find.descendant(
      of: tabs,
      matching: find.byType(FractionallySizedBox),
    );
    final indicatorLeft = tester.getTopLeft(indicator).dx;
    final gesture = await tester.startGesture(const Offset(320, 330));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-145, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pages.progress, inExclusiveRange(0, 1));
    expect(tester.getRect(tabs).left, closeTo(bar.left, .01));
    expect(tester.getTopLeft(indicator).dx, greaterThan(indicatorLeft));
    expect(feed.calls, [FeedTab.forYou]);
    await gesture.moveBy(const Offset(-135, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(feed.calls, [FeedTab.forYou, FeedTab.nearby]);
    expect(find.text('nearby post 0'), findsOneWidget);
  });

  for (final empty in [false, true]) {
    testWidgets('a collapsed header stays collapsed on swipe (empty=$empty)', (
      tester,
    ) async {
      final feed = _Feed();
      await _mount(tester, feed);
      final first = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      first.jumpTo(620);
      await tester.pumpAndSettle();
      expect(find.byTooltip('inbox').hitTestable(), findsNothing);
      if (empty) feed.next = Future.value(const FeedPageResult(posts: []));

      final gesture = await tester.startGesture(const Offset(320, 330));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-145, 0));
      await tester.pump();
      final incoming = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey((FeedTab.nearby, 0))),
          )
          .controller!;
      expect(incoming.offset, PrimaryHeaderGeometry.compactTabsContentTop);
      expect(find.byTooltip('inbox').hitTestable(), findsNothing);
      expect(feed.calls, [FeedTab.forYou]);

      await gesture.moveBy(const Offset(-135, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(incoming.offset, PrimaryHeaderGeometry.compactTabsContentTop);
      expect(find.byTooltip('inbox').hitTestable(), findsNothing);
      expect(feed.calls, [FeedTab.forYou, FeedTab.nearby]);
      expect(
        find.text(empty ? 'no posts yet' : 'nearby post 0'),
        findsOneWidget,
      );

      await tester.dragFrom(const Offset(45, 350), const Offset(270, 0));
      await tester.pumpAndSettle();
      expect(first.offset, 620);
      expect(find.byTooltip('inbox').hitTestable(), findsNothing);
      expect(feed.calls, [FeedTab.forYou, FeedTab.nearby]);
    });
  }

  testWidgets(
    'previously visited tabs use the same header in both directions',
    (tester) async {
      final feed = _Feed();
      await _mount(tester, feed);
      final inbox = find.byTooltip('inbox').hitTestable();
      final expanded = tester.getRect(inbox);
      await tester.tap(find.text('nearby'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('for you'));
      await tester.pumpAndSettle();

      final controller = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      controller.jumpTo(620);
      await tester.pumpAndSettle();
      expect(inbox, findsNothing);
      final toNearby = await tester.startGesture(const Offset(320, 330));
      await toNearby.moveBy(const Offset(-30, 0));
      await tester.pump();
      await toNearby.moveBy(const Offset(-145, 0));
      await tester.pump();
      final firstNearby = find.ancestor(
        of: find.text('nearby post 0'),
        matching: find.byType(Card),
      );
      expect(tester.getTopLeft(firstNearby).dy, closeTo(0, .01));
      expect(inbox, findsNothing);
      await toNearby.moveBy(const Offset(-135, 0));
      await toNearby.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstNearby).dy, closeTo(0, .01));
      expect(inbox, findsNothing);

      await tester.timedDragFrom(
        const Offset(180, 330),
        const Offset(0, 215),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(inbox), expanded);
      final back = await tester.startGesture(const Offset(45, 330));
      await back.moveBy(const Offset(30, 0));
      await tester.pump();
      await back.moveBy(const Offset(145, 0));
      await tester.pump();
      expect(tester.getRect(inbox), expanded);
      await back.moveBy(const Offset(135, 0));
      await back.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(inbox), expanded);
      expect(controller.offset, 620);
      expect(feed.calls, [FeedTab.forYou, FeedTab.nearby]);
    },
  );

  testWidgets('rotation keeps a collapsed header aligned with the list', (
    tester,
  ) async {
    await _mount(tester, _Feed(), size: const Size(844, 390));
    final list = find.byType(CustomScrollView);
    final controller = tester.widget<CustomScrollView>(list).controller!;
    controller.jumpTo(PrimaryHeaderGeometry.compactHeight);
    await tester.pumpAndSettle();
    expect(find.byTooltip('inbox').hitTestable(), findsNothing);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('inbox').hitTestable(), findsNothing);
    final firstCard = find.ancestor(
      of: find.text('forYou post 0'),
      matching: find.byType(Card),
    );
    expect(tester.getTopLeft(firstCard).dy, closeTo(0, .01));
  });

  testWidgets('the divider leaves equal space between consecutive posts', (
    tester,
  ) async {
    await _mount(tester, _Feed());
    final like = find.byIcon(Icons.favorite_border).first;
    final divider = find.byType(Divider).first;
    final avatar = find.byType(FeedPostAuthorAvatar).at(1);
    final line = tester.getCenter(divider).dy;
    final before = line - tester.getBottomLeft(like).dy;
    final after = tester.getTopLeft(avatar).dy - line;
    expect(before, greaterThanOrEqualTo(14));
    expect(before, closeTo(after, .01));
  });

  testWidgets('a swipe on the media strip stays inside that post', (
    tester,
  ) async {
    final feed = _Feed();
    feed.next = Future.value(
      FeedPageResult(
        posts: [
          FeedPost(
            id: 'media-post',
            authorId: 'author',
            authorName: 'author',
            text: 'media body',
            createdAt: DateTime.utc(2026),
            photos: const [
              FeedPhoto(id: '0', thumbnailPath: '0', width: 800, height: 1200),
              FeedPhoto(id: '1', thumbnailPath: '1', width: 1200, height: 800),
              FeedPhoto(id: '2', thumbnailPath: '2', width: 800, height: 800),
            ],
          ),
        ],
      ),
    );
    await _mount(tester, feed);
    final photos = find.byKey(
      const PageStorageKey(('feed-photos', 'media-post')),
    );
    expect(tester.getSize(photos).width, 360);
    final firstPhoto = find.descendant(
      of: photos,
      matching: find.byKey(const ValueKey('0')),
    );
    expect(
      tester.getTopLeft(firstPhoto).dx,
      tester.getTopLeft(find.text('media body')).dx,
    );
    final landscapePhoto = find.descendant(
      of: photos,
      matching: find.byKey(const ValueKey('1')),
    );
    expect(
      tester.getSize(firstPhoto).height,
      tester.getSize(landscapePhoto).height,
    );
    expect(tester.getSize(firstPhoto).aspectRatio, closeTo(2 / 3, .01));
    expect(tester.getSize(landscapePhoto).aspectRatio, closeTo(1.5, .01));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: photos, matching: find.byType(Scrollable)),
        )
        .position;
    await tester.drag(photos, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(feed.calls, [FeedTab.forYou]);
    expect(find.text('media body'), findsOneWidget);
  });

  testWidgets('returning across tabs keeps the first preview painted', (
    tester,
  ) async {
    final feed = _FeedWithPhotos();
    final accounts = AccountSessionController(initialUserId: 'viewer');
    final scope = FeedAccountScope(accounts, feed);
    addTearDown(scope.dispose);
    final post = FeedPost(
      id: 'cached',
      authorId: 'author',
      authorName: 'author',
      text: 'cached picture',
      createdAt: DateTime.utc(2026),
      photos: const [FeedPhoto(id: 'picture', thumbnailPath: 'thumb')],
    );
    feed.next = Future.value(FeedPageResult(posts: [post]));
    final image = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawPaint(ui.Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(24, 24);
      } finally {
        picture.dispose();
      }
    }))!;
    addTearDown(image.dispose);
    final frames = scope.actionsFor(accounts.capture())!.thumbnailFrames;
    frames.store(post, 'thumb', 208, image);
    final router = _FeedTabsRouter();
    addTearDown(router.dispose);
    await _mount(
      tester,
      feed,
      accounts: accounts,
      scope: scope,
      size: const Size(500, 900),
      router: router,
    );
    final preview = find.descendant(
      of: find.byKey(const PageStorageKey(('feed-photos', 'cached'))),
      matching: find.byType(RawImage),
    );
    expect(preview, findsOneWidget);
    final mountedPreview = tester.element(preview);
    expect(feed.thumbnailReads, isEmpty);
    frames.clear();

    await tester.tap(find.text('friends'));
    await tester.pumpAndSettle();
    expect(find.text('friends post 0'), findsOneWidget);
    await tester.tap(find.text('for you'));
    await tester.pump();
    expect(tester.element(preview), same(mountedPreview));
    await tester.pumpAndSettle();
    final tabs = AutoTabsRouter.of(tester.element(find.text('feed')));
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(find.text('other main tab'), findsOneWidget);
    tabs.setActiveIndex(0);
    await tester.pump();
    expect(tester.element(preview), same(mountedPreview));
    await tester.pumpAndSettle();
    expect(feed.calls, [FeedTab.forYou, FeedTab.friends]);
    expect(feed.thumbnailReads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape puts the tabs between title and inbox', (
    tester,
  ) async {
    await _mount(tester, _Feed(), size: const Size(844, 390));
    final tabs = find.byType(PrimarySegmentedControl);
    expect(
      find.ancestor(of: tabs, matching: find.byType(PrimaryAppBar)),
      findsOneWidget,
    );
    final title = tester.getRect(find.byType(ConnectionStatusTitle));
    final inbox = tester.getRect(find.byTooltip('inbox'));
    final tabBar = tester.getRect(tabs);
    expect(tabBar.left, greaterThan(title.right));
    expect(tabBar.right, lessThan(inbox.left));
  });

  testWidgets(
    'return to top affects only the current feed and makes no request',
    (tester) async {
      final feed = _Feed();
      final navigation = NavigationScrollToTopController();
      addTearDown(navigation.dispose);
      await _mount(tester, feed, navigation: navigation);
      final list = find.byType(CustomScrollView);
      final controller = tester.widget<CustomScrollView>(list).controller!;
      controller.jumpTo(600);
      await tester.pump();
      final done = navigation.scrollToTop(
        NavigationScrollTarget.recommendations,
      );
      await tester.pumpAndSettle();
      await done;
      expect(controller.offset, 0);
      expect(find.text('friends').hitTestable(), findsOneWidget);
      expect(feed.calls, [FeedTab.forYou]);
    },
  );

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
      await tester.tap(find.text('friends'));
      await tester.pumpAndSettle();
      expect(find.text('friends post 0'), findsOneWidget);
      final pending = Completer<FeedPageResult>();
      feed.next = pending.future;
      accounts.setAuthenticatedUser('new-viewer');
      await tester.pump();
      await tester.pump();
      expect(find.text('forYou post 0'), findsNothing);
      expect(find.text('friends post 0'), findsNothing);
      expect(feed.calls, [FeedTab.forYou, FeedTab.friends, FeedTab.forYou]);
      final indicator = tester.widget<PullRefreshIndicator>(
        find.byKey(const ValueKey('feed_pull_indicator')),
      );
      expect(indicator.opacity, 1);
      expect(indicator.size, 36);
      expect(indicator.spinning, isTrue);
      pending.complete(const FeedPageResult(posts: []));
      await tester.pumpAndSettle();
      final empty = find.text('no posts yet');
      expect(tester.widget<Text>(empty).style!.fontWeight, FontWeight.w700);
      expect(
        tester.widget<EmptyChatState>(find.byType(EmptyChatState)).showImage,
        isFalse,
      );
    },
  );

  testWidgets('failed feed uses the shared retry pill on the active tab', (
    tester,
  ) async {
    final feed = _Feed();
    await _mount(tester, feed);
    final pending = Completer<FeedPageResult>();
    feed.next = pending.future;
    await tester.tap(find.text('friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'try again');
    final style = tester.widget<FilledButton>(button).style!;
    expect(style.shape!.resolve({}), isA<StadiumBorder>());
    expect(
      style.backgroundColor!.resolve({}),
      Theme.of(tester.element(button)).colorScheme.primary,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(feed.calls, [FeedTab.forYou, FeedTab.friends, FeedTab.friends]);
    expect(find.text('friends post 0'), findsOneWidget);
  });
}

Future<AccountSessionController> _mount(
  WidgetTester tester,
  _Feed feed, {
  Size size = const Size(360, 800),
  NavigationScrollToTopController? navigation,
  ILocationRepository? location,
  AccountSessionController? accounts,
  FeedAccountScope? scope,
  RootStackRouter? router,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  accounts ??= AccountSessionController(initialUserId: 'viewer');
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AccountSessionController>.value(value: accounts),
        RepositoryProvider<IFeedRepository>.value(value: feed),
        if (scope != null) RepositoryProvider.value(value: scope),
        if (location != null) RepositoryProvider.value(value: location),
        if (navigation != null) RepositoryProvider.value(value: navigation),
      ],
      child: router == null
          ? MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const RecommendationsPage(),
            )
          : MaterialApp.router(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(),
            ),
    ),
  );
  await tester.pumpAndSettle();
  return accounts;
}

class _Location implements ILocationRepository {
  DateTime? publishedAt;
  Duration? maxAge;

  @override
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    this.maxAge = maxAge;
    final at = publishedAt;
    return at == null
        ? null
        : CachedTrackedLocation(latitude: 1, longitude: 1, updatedAt: at);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async => throw UnimplementedError();
}

class _FeedWithPhotos extends _Feed implements IFeedPostRepository {
  final thumbnailReads = <String>[];

  @override
  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) {
    thumbnailReads.add(photo.thumbnailPath);
    return super.downloadThumbnail(
      photo,
      post: post,
      account: account,
      stillNeeded: stillNeeded,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FeedTabsRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'Shell',
      path: '/',
      initial: true,
      builder: (_, _) => AutoTabsRouter(
        routes: const [
          PageRouteInfo('RecommendationsRoute'),
          PageRouteInfo('OtherTab'),
        ],
        duration: Duration.zero,
        transitionBuilder: (_, child, _) => child,
      ),
      children: [
        NamedRouteDef(
          name: 'RecommendationsRoute',
          path: 'feed',
          initial: true,
          builder: (_, _) => const RecommendationsPage(),
        ),
        NamedRouteDef(
          name: 'OtherTab',
          path: 'other',
          builder: (_, _) => const Scaffold(body: Text('other main tab')),
        ),
      ],
    ),
  ];
}
