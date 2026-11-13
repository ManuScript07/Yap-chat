import 'dart:io';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/main/main.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets(
    'repeat taps in the real shell return the active list without replacing routes',
    (tester) async {
      final router = await _mount(tester, scrollFixtures: true);
      final nav = find.byKey(const ValueKey('navigation_surface'));
      final tabs = AutoTabsRouter.of(tester.element(nav));
      for (final index in [0, 1, 3]) {
        final destination = find.byKey(
          ValueKey('navigation_destination_$index'),
        );
        await tester.tap(destination);
        await tester.pumpAndSettle();
        final page = switch (index) {
          0 => find.byType(ChatsPage),
          1 => find.byType(_NearbyScrollProbe),
          _ => find.byType(FriendsPage),
        };
        final element = tester.element(page);
        final list = find
            .descendant(of: page, matching: find.byType(ListView))
            .first;
        final controller = tester.widget<ListView>(list).controller!;
        expect(controller.position.maxScrollExtent, greaterThan(0));
        controller.jumpTo(controller.position.maxScrollExtent.clamp(0, 900));
        await tester.pump();
        final before = controller.offset;
        await tester.tap(destination);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.offset, inExclusiveRange(0, before));
        expect(tabs.activeIndex, index);
        await tester.pumpAndSettle();
        expect(controller.offset, 0);
        expect(tester.element(page), same(element));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );
  setUpAll(() async {
    AppTextStyles.chatName = const TextStyle(fontSize: 18, height: 1.33);
    AppTextStyles.messagePreview = const TextStyle(fontSize: 16, height: 1.25);
    AppTextStyles.metadata = const TextStyle(fontSize: 14, height: 1.14);
    AppTextStyles.badgeText = const TextStyle(fontSize: 14, height: 1.14);
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'production routes keep chat first and place recommendations in the center',
    () {
      final router = AppRouter();
      final main = router.routes.first.children!.firstWhere(
        (route) => route.page.name == MainRoute.name,
      );
      expect(main.children!.map((route) => route.page.name).toList(), [
        ChatsRoute.name,
        NearbyPeopleRoute.name,
        RecommendationsRoute.name,
        FriendsRoute.name,
        ProfileRoute.name,
      ]);
    },
  );

  for (final size in [const Size(360, 780), const Size(780, 360)]) {
    for (final safe in [15.0, 48.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'real chat/friend search gap and safe area $size safe=$safe scale=$scale',
          (tester) async {
            final router = await _mount(
              tester,
              size: size,
              safe: safe,
              scale: scale,
            );
            final nav = find.byKey(const ValueKey('navigation_surface'));
            Future<void> check() async {
              await tester.pumpAndSettle();
              final bar = tester.getRect(nav);
              final search = tester.getRect(
                find.byType(GlassSearchBar).hitTestable(),
              );
              expect(bar.top - search.bottom, closeTo(16, .1));
              expect(
                size.height - bar.bottom,
                closeTo((size.width > size.height ? 0 : safe) + 10, .1),
              );
              expect(tester.takeException(), isNull);
            }

            await check();
            await tester.tap(
              find.byKey(const ValueKey('navigation_destination_3')),
            );
            await check();
            expect(
              AutoTabsRouter.of(tester.element(nav)).current.name,
              FriendsRoute.name,
            );
            await tester.binding.handlePopRoute();
            await check();
            expect(
              AutoTabsRouter.of(tester.element(nav)).current.name,
              ChatsRoute.name,
            );
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'real shell retains cached avatar across five tabs, rotation and deletion',
    (tester) async {
      final capture = GlobalKey();
      final router = await _mount(
        tester,
        withAvatar: true,
        captureKey: capture,
      );
      final avatar = find.byType(ProfileNavigationAvatar);
      final image = find.descendant(of: avatar, matching: find.byType(Image));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        if (tester
            .widgetList<RawImage>(
              find.descendant(of: avatar, matching: find.byType(RawImage)),
            )
            .any((x) => x.image != null)) {
          break;
        }
      }
      final element = tester.element(image);
      for (final i in [1, 2, 3, 4]) {
        await tester.tap(find.byKey(ValueKey('navigation_destination_$i')));
        await tester.pump();
        expect(tester.element(image), same(element));
        expect(
          tester
              .widget<RawImage>(
                find.descendant(of: avatar, matching: find.byType(RawImage)),
              )
              .image,
          isNotNull,
        );
        await tester.pumpAndSettle();
      }
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final bitmap = await boundary.toImage(pixelRatio: 3);
        final bytes = (await bitmap.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        await File(
          'tmp/bottom_navigation_profile_avatar.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        bitmap.dispose();
      });
      tester.view.physicalSize = const Size(780, 360);
      await tester.pumpAndSettle();
      expect(tester.element(image), same(element));
      final auth = tester.element(avatar).read<AuthBloc>() as _AuthStub;
      auth.updateProfile(auth.state.profile!.copyWith(clearAvatarBytes: true));
      await tester.pump();
      expect(tester.element(image), same(element));
      expect(
        tester
            .widget<RawImage>(
              find.descendant(of: avatar, matching: find.byType(RawImage)),
            )
            .image,
        isNotNull,
      );
      auth.updateProfile(
        const UserProfile(
          id: 'owner',
          username: 'owner',
          displayName: 'Owner',
          onboardingCompleted: true,
          yandexAvatarDisabled: true,
        ),
      );
      await tester.pump();
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );

  testWidgets('tab pages never fade to black and keep their existing state', (
    tester,
  ) async {
    final router = await _mount(tester);
    final chats = tester.element(find.byType(ChatsPage));
    for (final i in [1, 4, 0, 3, 0]) {
      await tester.tap(find.byKey(ValueKey('navigation_destination_$i')));
      final page = switch (i) {
        1 => find.text('nearby'),
        4 => find.text('profile'),
        3 => find.byType(FriendsPage),
        _ => find.byType(ChatsPage),
      };
      for (final elapsed in [0, 16, 50, 180]) {
        await tester.pump(Duration(milliseconds: elapsed));
        expect(page, findsOneWidget);
        for (final fade in tester.widgetList<FadeTransition>(
          find.ancestor(of: page, matching: find.byType(FadeTransition)),
        )) {
          expect(fade.opacity.value, 1, reason: 'Tab $i, frame $elapsed ms');
        }
      }
      if (i == 0) expect(tester.element(page), same(chats));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets(
    'all five tab destinations and Back retain their route identities',
    (tester) async {
      final router = await _mount(tester);
      final nav = find.byKey(const ValueKey('navigation_surface'));
      const routes = [
        ChatsRoute.name,
        NearbyPeopleRoute.name,
        RecommendationsRoute.name,
        FriendsRoute.name,
        ProfileRoute.name,
      ];
      for (final i in [1, 2, 3, 4, 0]) {
        await tester.tap(find.byKey(ValueKey('navigation_destination_$i')));
        await tester.pumpAndSettle();
        expect(AutoTabsRouter.of(tester.element(nav)).current.name, routes[i]);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );
}

Future<_ShellRouter> _mount(
  WidgetTester tester, {
  Size size = const Size(360, 780),
  double safe = 15,
  double scale = 1,
  bool withAvatar = false,
  GlobalKey? captureKey,
  bool scrollFixtures = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = FakeViewPadding(
    bottom: safe,
    right: size.width > size.height ? 48 : 0,
  );
  addTearDown(tester.view.reset);
  final avatarBytes = withAvatar
      ? (await rootBundle.load(
          'assets/logo/logo_yap_chat.png',
        )).buffer.asUint8List()
      : null;
  final auth = _AuthStub(
    profile: UserProfile(
      id: 'owner',
      username: 'owner',
      displayName: 'Owner',
      onboardingCompleted: true,
      avatarBytes: avatarBytes,
      avatarStoragePath: withAvatar ? 'owner/photo' : null,
    ),
  );
  addTearDown(auth.close);
  final router = _ShellRouter(scrollFixtures: scrollFixtures);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IChatsRepository>(
          create: (_) => MockChatsRepository(),
        ),
        RepositoryProvider<IFriendsRepository>(
          create: (_) =>
              scrollFixtures ? _ManyFriends() : MockFriendsRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: auth),
          BlocProvider(
            create: (_) => PresenceCubit(repository: MockPresenceRepository()),
          ),
        ],
        child: MaterialApp.router(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: Colors.black,
          ),
          builder: (context, child) => RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _AuthStub extends Cubit<AuthState> implements AuthBloc {
  _AuthStub({UserProfile? profile})
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          profile:
              profile ??
              const UserProfile(
                id: 'owner',
                username: 'owner',
                displayName: 'Owner',
                onboardingCompleted: true,
              ),
        ),
      );
  void updateProfile(UserProfile profile) =>
      emit(state.copyWith(profile: profile));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellRouter extends RootStackRouter {
  _ShellRouter({this.scrollFixtures = false});
  final bool scrollFixtures;
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: MainRoute.name,
      path: '/',
      initial: true,
      builder: (_, _) => const MainPage(),
      children: [
        NamedRouteDef(
          name: ChatsRoute.name,
          path: 'chats',
          initial: true,
          builder: (_, _) => const ChatsPage(),
        ),
        NamedRouteDef(
          name: NearbyPeopleRoute.name,
          path: 'nearby',
          builder: (_, _) => scrollFixtures
              ? const _NearbyScrollProbe()
              : const Scaffold(body: Text('nearby')),
        ),
        AutoRoute(page: RecommendationsRoute.page, path: 'recommendations'),
        NamedRouteDef(
          name: FriendsRoute.name,
          path: 'friends',
          builder: (_, _) => const FriendsPage(),
        ),
        NamedRouteDef(
          name: ProfileRoute.name,
          path: 'profile',
          builder: (_, _) => const Scaffold(body: Text('profile')),
        ),
      ],
    ),
  ];
}

class _ManyFriends extends MockFriendsRepository {
  @override
  Stream<List<Friend>> watchFriends() => Stream.value(
    List.generate(
      30,
      (i) => Friend(
        id: 'f$i',
        username: 'friend$i',
        displayName: 'Friend $i',
        friendsSince: DateTime(2026),
      ),
    ),
  );
  @override
  Stream<FriendListCacheState> watchFriendListState() =>
      Stream.value(const FriendListCacheState(totalCount: 30, hasMore: false));
}

class _NearbyScrollProbe extends StatefulWidget {
  const _NearbyScrollProbe();
  @override
  State<_NearbyScrollProbe> createState() => _NearbyScrollProbeState();
}

class _NearbyScrollProbeState extends State<_NearbyScrollProbe> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: NavigationScrollToTopTarget(
      target: NavigationScrollTarget.nearby,
      controller: controller,
      child: ListView(
        controller: controller,
        children: [
          const Text('nearby'),
          for (var i = 0; i < 100; i++)
            SizedBox(height: 80, child: Text('row $i')),
        ],
      ),
    ),
  );
}
