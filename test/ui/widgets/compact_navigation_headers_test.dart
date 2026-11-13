import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/new_chat/new_chat.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/recommendations/recommendations.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets(
    'return from the friends bottom does not request pages and normal scrolling still can',
    (tester) async {
      final navigation = NavigationScrollToTopController();
      final f = await _mount(tester, page: 'friends', navigation: navigation);
      final controller = tester
          .widget<ListView>(find.byKey(const PageStorageKey('friends-list')))
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final requests = f.bloc.pageRequests;
      final done = navigation.scrollToTop(NavigationScrollTarget.friends);
      await tester.pumpAndSettle();
      await done;
      expect(controller.offset, 0);
      expect(f.bloc.pageRequests, requests);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(f.bloc.pageRequests, greaterThan(requests));
      final beforeCancellation = f.bloc.pageRequests;
      final cancelled = navigation.scrollToTop(NavigationScrollTarget.friends);
      navigation.cancel();
      await tester.pumpAndSettle();
      await cancelled;
      expect(f.bloc.pageRequests, beforeCancellation);
      expect(tester.takeException(), isNull);
      await f.close(tester);
      navigation.dispose();
    },
  );
  testWidgets('return preserves the friends query and input focus', (
    tester,
  ) async {
    final navigation = NavigationScrollToTopController();
    final f = await _mount(tester, page: 'friends', navigation: navigation);
    await tester.enterText(find.byType(TextField), 'friend');
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus;
    final controller = tester
        .widget<ListView>(find.byKey(const PageStorageKey('friends-list')))
        .controller!;
    controller.jumpTo(700);
    await tester.pump();
    final done = navigation.scrollToTop(NavigationScrollTarget.friends);
    await tester.pumpAndSettle();
    await done;
    expect(controller.offset, 0);
    expect(f.bloc.state.friendsQuery, 'friend');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'friend',
    );
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(f.repository.loads, 0);
    expect(tester.takeException(), isNull);
    await f.close(tester);
    navigation.dispose();
  });
  for (final size in [const Size(360, 800), const Size(844, 390)]) {
    testWidgets(
      'navigation scrolls only the selected friends/request list $size',
      (tester) async {
        _geometry(tester, size);
        final navigation = NavigationScrollToTopController();
        final f = await _mount(tester, page: 'friends', navigation: navigation);
        ScrollController activeController(String key) => tester
            .widget<ListView>(find.byKey(PageStorageKey(key)))
            .controller!;
        final friends = activeController('friends-list');
        friends.jumpTo(900);
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(PrimarySegmentedControl)),
        )!;
        await tester.tap(find.text(l10n.friendsTabRequests));
        await tester.pumpAndSettle();
        final requests = activeController('friend-requests-list');
        requests.jumpTo(800);
        await tester.pump();
        final done = navigation.scrollToTop(NavigationScrollTarget.friends);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(requests.offset, inExclusiveRange(0, 800));
        expect(friends.offset, 900);
        await tester.pumpAndSettle();
        await done;
        expect(requests.offset, 0);
        await tester.tap(
          find.descendant(
            of: find.byType(PrimarySegmentedControl),
            matching: find.text(l10n.friendsTabFriends),
          ),
        );
        await tester.pumpAndSettle();
        expect(friends.offset, 900);
        final back = navigation.scrollToTop(NavigationScrollTarget.friends);
        await tester.pumpAndSettle();
        await back;
        expect(friends.offset, 0);
        expect(f.repository.loads, 0);
        expect(f.bloc.state.friends.length, 30);
        expect(f.bloc.state.requests.length, 30);
        expect(tester.takeException(), isNull);
        await f.close(tester);
        navigation.dispose();
      },
    );
  }
  testWidgets('legacy and settings headers retain their size and typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Scaffold(appBar: PrimaryAppBar(title: 'legacy'))),
    );
    expect(
      tester
          .widget<PrimaryAppBar>(find.byType(PrimaryAppBar))
          .preferredSize
          .height,
      130,
    );
    expect(
      tester.widget<Text>(find.text('legacy')).style,
      AppTextStyles.titleLargeFlex,
    );
    await tester.pumpWidget(
      _app(const Scaffold(appBar: SettingsPageAppBar(title: 'settings'))),
    );
    expect(
      tester
          .widget<SettingsPageAppBar>(find.byType(SettingsPageAppBar))
          .preferredSize
          .height,
      130,
    );
    expect(tester.widget<Text>(find.text('settings')).style!.fontSize, 32);
  });

  for (final page in ['friends', 'recommendations', 'new-chat']) {
    for (final size in [const Size(360, 800), const Size(844, 390)]) {
      for (final locale in ['ru', 'en']) {
        for (final scale in [1.0, 1.5, 2.0]) {
          testWidgets('$page compact header fits $size $locale scale=$scale', (
            tester,
          ) async {
            _geometry(tester, size);
            final fixture = await _mount(
              tester,
              page: page,
              locale: locale,
              scale: scale,
            );
            final header = find.byType(PrimaryAppBar);
            final bar = tester.widget<PrimaryAppBar>(header);
            expect(
              bar.preferredSize.height,
              PrimaryHeaderGeometry.compactHeight,
            );
            final l10n = AppLocalizations.of(tester.element(header))!;
            final label = switch (page) {
              'friends' => l10n.navFriends,
              'recommendations' => l10n.recommendationsTitle,
              _ => l10n.newChatTitle,
            };
            final title = tester.widget<Text>(
              find.descendant(of: header, matching: find.text(label)).first,
            );
            expect(
              title.style!.fontSize,
              PrimaryHeaderGeometry.compactTitleSize,
            );
            expect(tester.takeException(), isNull);
            if (page != 'new-chat') {
              final before = tester.getRect(header);
              fixture.status.reportNetworkAvailability(false);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              final connecting = find.byType(AnimatedConnectingText);
              expect(connecting, findsOneWidget);
              expect(
                tester.getRect(connecting).left,
                greaterThanOrEqualTo(before.left),
              );
              expect(
                tester.getRect(connecting).right,
                lessThanOrEqualTo(before.right),
              );
              expect(tester.getRect(header), before);
              expect(fixture.repository.loads, 0);
              expect(tester.takeException(), isNull);
              fixture.status.reportNetworkAvailability(true);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              expect(find.byType(AnimatedConnectingText), findsNothing);
            }
            await fixture.close(tester);
          });
        }
      }
    }
  }

  for (final size in [const Size(360, 800), const Size(844, 390)]) {
    testWidgets(
      'friends retain search focus with compact chrome and IME $size',
      (tester) async {
        _geometry(tester, size);
        final fixture = await _mount(tester, page: 'friends');
        await tester.tap(find.byType(TextField));
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(
          find.byType(PrimaryAppBar),
          size.width > size.height ? findsNothing : findsOneWidget,
        );
        expect(find.byType(PrimarySegmentedControl), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(find.byType(PrimaryAppBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      },
    );
    testWidgets(
      'friends and requests scroll below chrome and preserve offsets $size',
      (tester) async {
        _geometry(tester, size);
        final fixture = await _mount(tester, page: 'friends');
        final tabs = find.byType(PrimarySegmentedControl);
        expect(
          tester.getSize(tabs).height,
          PrimaryHeaderGeometry.compactTabsHeight,
        );
        final l10n = AppLocalizations.of(tester.element(tabs))!;
        final friends = find.byKey(const PageStorageKey('friends-list'));
        expect(tester.getTopLeft(friends).dy, 0);
        expect(
          (tester.widget<ListView>(friends).padding! as EdgeInsets).top,
          closeTo(
            size.width > size.height
                ? 80
                : PrimaryHeaderGeometry.compactTabsContentTop,
            .01,
          ),
        );
        if (size.width < size.height) {
          expect(
            tester.getTopLeft(tabs).dy,
            PrimaryHeaderGeometry.compactTabsTop,
          );
        }
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: friends, matching: find.byType(Scrollable)),
            )
            .position;
        position.jumpTo(120);
        await tester.pump();
        final section = find
            .descendant(of: friends, matching: find.byType(FriendsSectionTitle))
            .first;
        expect(
          tester.getTopLeft(section).dy,
          lessThan(tester.getRect(tabs).bottom),
        );
        final tabRect = tester.getRect(tabs);
        await tester.tap(
          find.descendant(
            of: tabs,
            matching: find.text(l10n.friendsTabRequests),
          ),
        );
        await tester.pumpAndSettle();
        final requests = find.byKey(
          const PageStorageKey('friend-requests-list'),
        );
        expect(tester.getTopLeft(requests).dy, 0);
        final requestPosition = tester
            .state<ScrollableState>(
              find.descendant(of: requests, matching: find.byType(Scrollable)),
            )
            .position;
        requestPosition.jumpTo(120);
        await tester.pump();
        final requestSection = find
            .descendant(
              of: requests,
              matching: find.byType(FriendsSectionTitle),
            )
            .first;
        expect(tester.getTopLeft(requestSection).dy, lessThan(tabRect.bottom));
        expect(tester.getRect(tabs), tabRect);
        await tester.tap(
          find.descendant(
            of: tabs,
            matching: find.text(l10n.friendsTabFriends),
          ),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, 120);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      },
    );
  }
}

Widget _app(Widget home, {String locale = 'en', double scale = 1}) =>
    MaterialApp(
      theme: ThemeData.dark(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding:
              MediaQuery.sizeOf(context).width >
                  MediaQuery.sizeOf(context).height
              ? const EdgeInsets.only(left: 28, right: 12)
              : const EdgeInsets.only(top: 24),
        ),
        child: child!,
      ),
      home: home,
    );

void _geometry(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  required String page,
  String locale = 'ru',
  double scale = 1,
  NavigationScrollToTopController? navigation,
}) async {
  final fixture = _Fixture();
  final home = switch (page) {
    'friends' => const FriendsPage(),
    'recommendations' => const RecommendationsPage(),
    _ => const NewChatPage(),
  };
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        if (navigation != null)
          RepositoryProvider<NavigationScrollToTopController>.value(
            value: navigation,
          ),
        RepositoryProvider<IFriendsRepository>.value(value: fixture.repository),
        RepositoryProvider<AppConnectionStatus>.value(value: fixture.status),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<FriendsBloc>.value(value: fixture.bloc),
          BlocProvider<PresenceCubit>.value(value: fixture.presence),
        ],
        child: _app(home, locale: locale, scale: scale),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

class _Fixture {
  final repository = _ManyFriends();
  late final bloc = _CountingFriendsBloc(repository)
    ..add(const FriendsLoadStarted());
  final presence = PresenceCubit(repository: MockPresenceRepository());
  final status = AppConnectionStatus(
    accountSessionController: AccountSessionController(initialUserId: 'u'),
    presentationDelay: Duration.zero,
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
    await tester.runAsync(presence.close);
    status.dispose();
  }
}

class _CountingFriendsBloc extends FriendsBloc {
  _CountingFriendsBloc(IFriendsRepository repository)
    : super(repository: repository);
  int pageRequests = 0;
  @override
  void add(FriendsEvent event) {
    if (event is FriendsLoadMoreRequested) pageRequests++;
    super.add(event);
  }
}

class _ManyFriends extends MockFriendsRepository {
  int loads = 0;
  final rows = List.generate(
    30,
    (i) => Friend(
      id: 'f$i',
      username: 'friend$i',
      displayName: 'Friend $i',
      friendsSince: DateTime(2026, 1, i + 1),
    ),
  );
  @override
  Stream<List<Friend>> watchFriends() => Stream.value(rows);
  @override
  Stream<FriendListCacheState> watchFriendListState() => Stream.value(
    FriendListCacheState(totalCount: rows.length, hasMore: false),
  );
  @override
  Stream<List<FriendRequest>> watchRequests() => Stream.value(
    List.generate(
      30,
      (i) => FriendRequest(
        id: 'r$i',
        peerId: 'p$i',
        peerUsername: 'peer$i',
        peerDisplayName: 'Peer $i',
        direction: i.isEven
            ? FriendRequestDirection.incoming
            : FriendRequestDirection.outgoing,
        requestedAt: DateTime(2026, 1, i + 1),
      ),
    ),
  );
  @override
  Future<void> loadMoreFriends() async {
    loads++;
  }
}
