import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/repositories/repositories.dart';

const _path = 'owner/stable-avatar.png';
const _url = 'https://example.invalid/avatar?signature=old';

void main() {
  for (final cached in [false, true]) {
    testWidgets(
      'real viewed profile preserves its avatar Hero on open/close cached=$cached',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final photo = ProfilePhoto(
          position: 0,
          storagePath: _path,
          bytes: File('assets/logo/logo_yap_chat.png').readAsBytesSync(),
        );
        final repository = _HeroProfileRepository(
          preferences,
          ViewedProfile(
            profile: UserProfile(
              id: 'owner',
              username: 'peer',
              displayName: 'Peer',
              onboardingCompleted: true,
              photos: [photo],
            ),
            relationship: ProfileRelationship.none,
            friendCount: 0,
            friendsPreview: const [],
            viewCount: 1,
            showsLastSeen: true,
          ),
          cached,
        );
        final blocks = MockBlocklistRepository();
        final f = await _mount(
          tester,
          source: 'chat',
          wrap: (app) => MultiRepositoryProvider(
            providers: [
              RepositoryProvider<IProfileRepository>.value(value: repository),
              RepositoryProvider<IFriendsRepository>(
                create: (_) => MockFriendsRepository(),
              ),
              RepositoryProvider<IChatsRepository>(
                create: (_) => MockChatsRepository(),
              ),
              RepositoryProvider<ILocationRepository>(
                create: (_) => LocationRepository(preferences: preferences),
              ),
              RepositoryProvider<ISettingsRepository>(
                create: (_) => MockSettingsRepository(),
              ),
              RepositoryProvider<IBlocklistRepository>.value(value: blocks),
              RepositoryProvider<IUserReportsRepository>(
                create: (_) => const MockUserReportsRepository(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (_) =>
                      PresenceCubit(repository: MockPresenceRepository()),
                ),
                BlocProvider(create: (_) => BlocklistCubit(repository: blocks)),
              ],
              child: app,
            ),
          ),
        );
        f.navigator.currentState!.push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 500),
            reverseTransitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, _, _) => const ViewedProfilePage(userId: 'owner'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(_flight(tester), findsOneWidget);
        _expectOnlyAnimatedMask(tester);
        repository.ready.complete(repository.value);
        await tester.pumpAndSettle();
        expect(find.byType(ViewedProfilePage), findsOneWidget);
        final profileHero = tester.widget<ProfilePhotoHero>(
          find.byType(ProfilePhotoHero),
        );
        expect(profileHero.borderRadius, closeTo(35.2, .001));
        // Exercise the real profile -> gallery route, not only a synthetic Hero.
        final plaque = find.descendant(
          of: find.byType(ProfilePhotoUsernameTransition, skipOffstage: false),
          matching: find.byType(AnimatedOpacity, skipOffstage: false),
        );
        expect(
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
          1,
        );
        await tester.tapAt(tester.getCenter(find.byType(ProfilePhotoHero)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        for (var i = 0; i < 40 && _flight(tester).evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(_flight(tester), findsOneWidget);
        expect(
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
          closeTo(1, .01),
        );
        await tester.pump(const Duration(milliseconds: 130));
        expect(
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
          0,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProfileGalleryPage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(_flight(tester), findsOneWidget);
        expect(
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
          0,
        );
        await tester.pumpAndSettle();
        expect(
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
          1,
        );
        f.navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        var previous = 35.2;
        for (var i = 0; i < 8; i++) {
          final radius = _flightRadius(tester);
          expect(radius, lessThanOrEqualTo(previous + .001));
          expect(radius, greaterThanOrEqualTo(20));
          _expectOnlyAnimatedMask(tester);
          previous = radius;
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ViewedProfilePage), findsNothing);
        expect(tester.getSize(find.byType(UserAvatar)), const Size(50, 50));
        expect(f.loaderCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final changePhoto in [false, true]) {
      testWidgets(
        'real profile gallery opens and closes with correct Hero $size changePhoto=$changePhoto',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final f = await _mount(tester, source: 'profile');
          f.navigator.currentState!.push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 260),
              reverseTransitionDuration: const Duration(milliseconds: 180),
              pageBuilder: (_, _, _) => ProfileGalleryPage(
                photos: [
                  f.photo,
                  f.photo.copyWith(
                    position: 1,
                    storagePath: 'owner/second.png',
                  ),
                ],
                initialIndex: 0,
                displayName: 'Peer',
                initialThumbnailCacheWidth: 352,
                imageAspectRatios: const [1, 1],
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
          var previous = 35.2;
          for (var i = 0; i < 6; i++) {
            final radius = _flightRadius(tester);
            expect(radius, lessThanOrEqualTo(previous + .001));
            expect(radius, greaterThanOrEqualTo(0));
            _expectOnlyAnimatedMask(tester);
            previous = radius;
            await tester.pump(const Duration(milliseconds: 35));
          }
          await tester.pumpAndSettle();
          if (changePhoto) {
            tester
                .widget<PageView>(find.byType(PageView))
                .controller!
                .jumpToPage(1);
            await tester.pumpAndSettle();
          }
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
          // PopScope first rebuilds the permitted pop, then Hero inserts its
          // overlay from the next post-frame callback.
          await tester.pump();
          previous = 0;
          for (var i = 0; i < 5; i++) {
            if (changePhoto) {
              expect(
                _flight(tester),
                findsNothing,
                reason:
                    'A different photo must not fly back into the initial avatar.',
              );
            } else {
              final radius = _flightRadius(tester);
              expect(radius, greaterThanOrEqualTo(previous - .001));
              expect(radius, lessThanOrEqualTo(35.2));
              previous = radius;
              _expectOnlyAnimatedMask(tester);
            }
            await tester.pump(const Duration(milliseconds: 25));
          }
          await tester.pumpAndSettle();
          expect(find.byType(ProfileGalleryPage), findsNothing);
          expect(
            tester
                .widget<ProfilePhotoHero>(find.byType(ProfilePhotoHero))
                .borderRadius,
            closeTo(35.2, .001),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'chat avatar matches the entire button including its rim at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            Scaffold(
              appBar: ChatAppBar(
                userName: 'Peer',
                isOnline: true,
                onBack: () {},
              ),
            ),
          ),
        );
        final avatar = find.byType(UserAvatar);
        final button = find.byType(GlassIconButton);
        final rim = find.descendant(
          of: button,
          matching: find.byType(ChatGlassSurface),
        );
        expect(tester.getSize(avatar), const Size(50, 50));
        expect(tester.getSize(button), tester.getSize(avatar));
        expect(tester.getSize(rim), tester.getSize(avatar));
        expect(tester.getTopLeft(button).dy, tester.getTopLeft(avatar).dy);
        expect(
          tester.widget<UserAvatar>(avatar).borderRadius,
          tester.widget<GlassIconButton>(button).borderRadius,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  test(
    'profile radius is gentler while list avatars keep their common proportion',
    () {
      expect(AvatarGeometry.profileRadiusFor(176), closeTo(35.2, 1e-12));
      expect(
        AvatarGeometry.profileRadiusFor(176),
        lessThan(AvatarGeometry.radiusFor(176)),
      );
      expect(const UserAvatar(size: 54).borderRadius / 54, closeTo(.4, 1e-12));
      expect(const UserAvatar(size: 56).borderRadius / 56, closeTo(.4, 1e-12));
    },
  );
  testWidgets(
    'opening during a pending avatar load does not start a second resolver',
    (tester) async {
      final pending = Completer<String?>();
      final navigator = GlobalKey<NavigatorState>();
      final bytes = File('assets/logo/logo_yap_chat.png').readAsBytesSync();
      var loads = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox.square(
              dimension: 54,
              child: ProfileAvatarHero(
                avatarUrl: _url,
                avatarStoragePath: 'cold/$_path',
                child: UserAvatar(
                  avatarUrl: _url,
                  avatarRevision: 'cold/$_path',
                  preferAvatarLoader: true,
                  avatarLoader: () {
                    loads++;
                    return pending.future;
                  },
                  size: 54,
                ),
              ),
            ),
          ),
          navigator: navigator,
        ),
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 176,
                child: ProfilePhotoHero(
                  photo: ProfilePhoto(
                    position: 0,
                    storagePath: 'cold/$_path',
                    bytes: bytes,
                  ),
                  borderRadius: AvatarGeometry.profileRadiusFor(176),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(loads, 1);
      final shuttleAvatars = tester.widgetList<UserAvatar>(
        find.descendant(of: _flight(tester), matching: find.byType(UserAvatar)),
      );
      expect(shuttleAvatars, hasLength(1));
      expect(shuttleAvatars.single.avatarLoader, isNull);
      expect(shuttleAvatars.single.avatarUrl, isNull);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a lazily resolved avatar is reused during Hero without another resolver call',
    (tester) async {
      final f = await _mount(
        tester,
        source: 'friends',
        provideInitialPath: false,
      );
      expect(f.loaderCalls, 1);
      f.navigator.currentState!.push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 176,
                child: ProfilePhotoHero(
                  photo: f.photo,
                  borderRadius: AvatarGeometry.profileRadiusFor(176),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(f.loaderCalls, 1);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(f.loaderCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'avatar corners use the same proportion as the 50px chat/profile control',
    () {
      expect(AvatarGeometry.radiusFor(50), 20);
      for (final size in [
        22.0,
        30.0,
        44.0,
        48.0,
        54.0,
        56.0,
        112.0,
        176.0,
        220.0,
      ]) {
        expect(UserAvatar(size: size).borderRadius / size, closeTo(.4, 1e-12));
      }
      expect(const UserAvatar(size: 128, borderRadius: 8).borderRadius, 8);
      expect(const UserAvatar(size: 22, borderRadius: 11).borderRadius, 11);
    },
  );

  for (final source in ['chat', 'friends', 'nearby', 'profile']) {
    for (final loading in [false, true]) {
      if (source == 'profile' && loading) continue;
      testWidgets(
        '$source Hero has a single animated corner mask on push/pop loading=$loading',
        (tester) async {
          final f = await _mount(tester, source: source);
          final beforeTag = tester.widget<Hero>(find.byType(Hero)).tag;
          expect(beforeTag, 'profile-photo-$_path');
          final sourceRadius = source == 'nearby'
              ? 8.0
              : source == 'profile'
              ? AvatarGeometry.profileRadiusFor(f.sourceSize)
              : AvatarGeometry.radiusFor(f.sourceSize);
          final targetRadius = source == 'profile'
              ? 0.0
              : AvatarGeometry.profileRadiusFor(176);
          final loadingState = ValueNotifier(loading);
          final route = PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 500),
            reverseTransitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, _, _) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: source == 'profile' ? 360 : 176,
                  height: source == 'profile' ? 240 : 176,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: loadingState,
                    builder: (_, waiting, _) {
                      if (waiting) {
                        return ProfileAvatarHero(
                          avatarUrl: _url,
                          avatarStoragePath: _path,
                          child: UserAvatar(
                            avatarImage: MemoryImage(f.bytes),
                            size: 176,
                            borderRadius: AvatarGeometry.profileRadiusFor(176),
                          ),
                        );
                      }
                      return ProfilePhotoHero(
                        photo: f.photo,
                        borderRadius: targetRadius,
                        fit: source == 'profile'
                            ? BoxFit.contain
                            : BoxFit.cover,
                        cacheWidth: 352,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          f.navigator.currentState!.push(route);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
          var previous = sourceRadius;
          for (var i = 0; i < 9; i++) {
            final radius = _flightRadius(tester);
            _expectOnlyAnimatedMask(tester);
            expect(
              radius,
              inInclusiveRange(
                sourceRadius < targetRadius ? sourceRadius : targetRadius,
                sourceRadius > targetRadius ? sourceRadius : targetRadius,
              ),
            );
            if (sourceRadius <= targetRadius) {
              expect(radius, greaterThanOrEqualTo(previous - .001));
            } else {
              expect(radius, lessThanOrEqualTo(previous + .001));
            }
            if (source != 'profile') {
              final side = tester.getSize(_flight(tester)).shortestSide;
              final t = (side - f.sourceSize) / (176 - f.sourceSize);
              expect(
                radius,
                closeTo(sourceRadius + (targetRadius - sourceRadius) * t, .001),
              );
            }
            previous = radius;
            if (loading && i == 2) loadingState.value = false;
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('profile-photo-flight-clip')),
            findsNothing,
          );
          expect(tester.widget<Hero>(find.byType(Hero)).tag, beforeTag);
          expect(f.loaderCalls, 0);

          f.navigator.currentState!.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
          previous = targetRadius;
          for (var i = 0; i < 9; i++) {
            final radius = _flightRadius(tester);
            _expectOnlyAnimatedMask(tester);
            if (sourceRadius <= targetRadius) {
              expect(radius, lessThanOrEqualTo(previous + .001));
            } else {
              expect(radius, greaterThanOrEqualTo(previous - .001));
            }
            if (source != 'profile') {
              final side = tester.getSize(_flight(tester)).shortestSide;
              final t = (side - f.sourceSize) / (176 - f.sourceSize);
              expect(
                radius,
                closeTo(sourceRadius + (targetRadius - sourceRadius) * t, .001),
              );
            }
            previous = radius;
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();
          expect(f.loaderCalls, 0);
          expect(tester.takeException(), isNull);
          expect(tester.widget<Hero>(find.byType(Hero)).tag, beforeTag);
          await tester.pumpWidget(const SizedBox.shrink());
          loadingState.dispose();
        },
      );
    }
  }

  testWidgets(
    'both Hero endpoint builders use the same geometry and stable storage tag',
    (tester) async {
      final f = await _mount(tester, source: 'friends');
      final from = tester.widget<Hero>(find.byType(Hero));
      await tester.pumpWidget(
        _app(
          const SizedBox.square(
            dimension: 176,
            child: ProfilePhotoHero(
              photo: ProfilePhoto(
                position: 0,
                storagePath: _path,
                avatarUrl: 'https://example.invalid/avatar?signature=new',
              ),
              borderRadius: 35.2,
            ),
          ),
        ),
      );
      final to = tester.widget<Hero>(find.byType(Hero));
      expect(from.tag, to.tag);
      expect(from.flightShuttleBuilder, to.flightShuttleBuilder);
      expect(f.loaderCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'missing avatars keep their normal placeholder with proportional corners',
    (tester) async {
      for (final size in [30.0, 48.0, 54.0, 176.0, 220.0]) {
        await tester.pumpWidget(_app(Center(child: UserAvatar(size: size))));
        final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
        expect(clip.borderRadius, BorderRadius.circular(size * .4));
        expect(find.byIcon(Icons.person), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Finder _flight(WidgetTester tester) =>
    find.byKey(const ValueKey('profile-photo-flight-clip'));

double _flightRadius(WidgetTester tester) => tester
    .widget<ClipRRect>(_flight(tester))
    .borderRadius
    .resolve(TextDirection.ltr)
    .topLeft
    .x;

void _expectOnlyAnimatedMask(WidgetTester tester) {
  final innerClips = tester.widgetList<ClipRRect>(
    find.descendant(of: _flight(tester), matching: find.byType(ClipRRect)),
  );
  expect(
    innerClips.every((clip) => clip.borderRadius == BorderRadius.zero),
    isTrue,
    reason: 'A static inner clip must not override interpolated Hero corners.',
  );
  final avatars = tester.widgetList<UserAvatar>(
    find.descendant(of: _flight(tester), matching: find.byType(UserAvatar)),
  );
  expect(
    avatars.every(
      (avatar) => avatar.borderRadius == 0 && !avatar.showOnlineBadge,
    ),
    isTrue,
  );
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  required String source,
  bool provideInitialPath = true,
  Widget Function(Widget)? wrap,
}) async {
  final bytes = File('assets/logo/logo_yap_chat.png').readAsBytesSync();
  final directory = Directory.systemTemp.createTempSync('yap-avatar-hero-');
  addTearDown(() async {
    await tester.runAsync(() async {
      // The production avatar's asynchronous LRU timestamp touch may still own
      // a Windows file handle after its widget has unmounted.
      for (var attempt = 0; ; attempt++) {
        try {
          await directory.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 9) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    });
  });
  final path = '${directory.path}/avatar.png';
  File(path).writeAsBytesSync(bytes);
  final f = _Fixture(
    bytes,
    source == 'chat'
        ? ChatAppBar.controlSize
        : source == 'friends'
        ? 54
        : source == 'nearby'
        ? 128
        : 176,
  );
  final photo = f.photo;
  final Widget hero = source == 'profile'
      ? ProfilePhotoHero(
          photo: photo,
          borderRadius: AvatarGeometry.profileRadiusFor(176),
          cacheWidth: 352,
        )
      : ProfileAvatarHero(
          profileId: 'owner',
          avatarUrl: _url,
          avatarStoragePath: _path,
          child: UserAvatar(
            size: f.sourceSize,
            borderRadius: source == 'nearby' ? 8 : null,
            avatarUrl: _url,
            // This fixture explicitly exercises a cold resolver. Earlier
            // gallery flights are allowed to retain their own warm revisions.
            avatarRevision: provideInitialPath ? _path : 'cold-resolved/$_path',
            initialAvatarPath: provideInitialPath ? path : null,
            avatarLoader: () async {
              f.loaderCalls++;
              return path;
            },
            preferAvatarLoader: true,
            showOnlineBadge: source == 'friends',
            isOnline: source == 'friends',
          ),
        );
  final app = _app(
    Scaffold(
      appBar: source == 'chat'
          ? ChatAppBar(
              userName: 'Peer',
              isOnline: true,
              profileId: 'owner',
              avatarUrl: _url,
              avatarStoragePath: _path,
              initialAvatarPath: path,
              avatarRevision: _path,
              avatarLoader: () async {
                f.loaderCalls++;
                return path;
              },
            )
          : null,
      body: source == 'chat'
          ? const SizedBox.shrink()
          : Center(
              child: SizedBox.square(dimension: f.sourceSize, child: hero),
            ),
    ),
    navigator: f.navigator,
  );
  await tester.pumpWidget(wrap?.call(app) ?? app);
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((raw) => raw.image != null)) {
      return f;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('The source image must be decoded before starting its Hero.');
}

Widget _app(Widget child, {GlobalKey<NavigatorState>? navigator}) =>
    MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class _Fixture {
  _Fixture(this.bytes, this.sourceSize);
  final Uint8List bytes;
  final double sourceSize;
  final navigator = GlobalKey<NavigatorState>();
  int loaderCalls = 0;
  ProfilePhoto get photo =>
      ProfilePhoto(position: 0, storagePath: _path, bytes: bytes);
}

class _HeroProfileRepository extends MockProfileRepository {
  _HeroProfileRepository(SharedPreferences preferences, this.value, this.cached)
    : super(preferences: preferences);
  final ViewedProfile value;
  final bool cached;
  final ready = Completer<ViewedProfile>();
  @override
  Future<ViewedProfile?> getCachedViewedProfile(String userId) async =>
      cached ? value : null;
  @override
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) => ready.future;
}
