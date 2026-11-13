import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'rapid relationship changes preserve layout on a narrow scaled screen',
    (tester) async {
      final f = await _mount(tester, size: const Size(320, 720), scale: 1.8);
      f.profiles.ready.complete(f.value);
      await tester.pumpAndSettle();
      final avatar = tester.getRect(find.byType(ProfilePhotoHero));
      for (final direction in [
        FriendRequestDirection.incoming,
        FriendRequestDirection.outgoing,
        null,
        FriendRequestDirection.incoming,
        null,
      ]) {
        f.friends.requests.add(
          direction == null
              ? []
              : [
                  FriendRequest(
                    id: 'request',
                    peerId: f.id,
                    peerUsername: 'peer',
                    peerDisplayName: 'Peer',
                    direction: direction,
                    requestedAt: DateTime(2026),
                  ),
                ],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 35));
        expect(tester.getRect(find.byType(ProfilePhotoHero)), avatar);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(f.profiles.reads, 1);
      expect(f.friends.distanceReads, 1);
      expect(f.friends.sendCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  testWidgets(
    'a block hides old relationship and distance immediately during their fade',
    (tester) async {
      final f = await _mount(tester);
      f.profiles.ready.complete(f.value);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ViewedProfilePage));
      final l10n = AppLocalizations.of(context)!;
      f.friends.requests.add([
        FriendRequest(
          id: 'request',
          peerId: f.id,
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
          direction: FriendRequestDirection.outgoing,
          requestedAt: DateTime(2026),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await context.read<IBlocklistRepository>().blockUser(
        BlockedUser(
          id: f.id,
          username: 'peer',
          displayName: 'Peer',
          blockedAt: DateTime(2026),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-distance-switch')),
        findsNothing,
      );
      expect(find.text(l10n.viewedProfileAddFriend), findsNothing);
      expect(find.text(l10n.viewedProfileRequestSent), findsNothing);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(720, 320),
  ]) {
    testWidgets('cold content fades in without moving its avatar $size', (
      tester,
    ) async {
      final f = await _mount(tester, size: size);
      final loading = tester.getRect(
        find.byKey(const ValueKey('profile-loading-avatar')),
      );
      final spinner = tester.getRect(find.byType(CircularProgressIndicator));
      f.profiles.ready.complete(f.value);
      await tester.pump();
      final metadata = find.byKey(const ValueKey('profile-metadata-reveal'));
      double opacity() => tester.widget<FadeTransition>(metadata).opacity.value;
      final hero = find.byType(ProfilePhotoHero);
      final plaque = find.descendant(
        of: find.byType(ProfilePhotoUsernameTransition),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
        1,
        reason:
            'Username must share the existing metadata fade without another delayed entrance.',
      );
      final target = tester.getRect(hero);
      expect(target, loading);
      expect(opacity(), 0);
      expect(tester.getRect(find.byType(CircularProgressIndicator)), spinner);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), inExclusiveRange(0, 1));
      expect(tester.getRect(hero), target);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(
        tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value,
        1,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getRect(hero), target);
      expect(f.profiles.reads, 1);
      expect(f.friends.distanceReads, 1);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  for (final size in [const Size(320, 720), const Size(780, 390)]) {
    for (final scale in [1.0, 2.0]) {
      for (final snapshot in [false, true]) {
        testWidgets(
          'load error stays below the avatar $size scale=$scale snapshot=$snapshot',
          (tester) async {
            final f = await _mount(
              tester,
              size: size,
              scale: scale,
              snapshot: snapshot,
            );
            f.profiles.ready.completeError(StateError('offline'));
            await tester.pumpAndSettle();
            final error = find.byKey(const ValueKey('profile-load-error'));
            expect(error, findsOneWidget);
            if (snapshot) {
              final avatar = find.byKey(
                const ValueKey('profile-loading-avatar'),
              );
              expect(
                tester.getRect(error).overlaps(tester.getRect(avatar)),
                isFalse,
              );
              expect(
                tester.getTopLeft(error).dy,
                greaterThan(tester.getRect(avatar).bottom),
              );
            }
            final scrollable = find.descendant(
              of: find.byKey(const ValueKey('profile-loading-viewport')),
              matching: find.byType(Scrollable),
            );
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.maxScrollExtent > 0) {
              await tester.drag(scrollable, const Offset(0, -170));
              await tester.pumpAndSettle();
              if (snapshot) {
                expect(
                  tester
                      .getRect(error)
                      .overlaps(
                        tester.getRect(
                          find.byKey(const ValueKey('profile-loading-avatar')),
                        ),
                      ),
                  isFalse,
                );
              }
            }
            expect(find.byType(SnackBar), findsNothing);
            expect(f.profiles.reads, 1);
            expect(tester.takeException(), isNull);
            await f.close(tester);
          },
        );
      }
    }
  }
  testWidgets(
    'late distance and relationship states crossfade without replaying profile entrance',
    (tester) async {
      final f = await _mount(tester);
      f.profiles.ready.complete(f.value);
      await tester.pumpAndSettle();
      final pageContext = tester.element(find.byType(ViewedProfilePage));
      final l10n = AppLocalizations.of(pageContext)!;
      final initial = tester.getRect(find.byType(ProfilePhotoHero));
      f.friends.requests.add([
        FriendRequest(
          id: 'request',
          peerId: f.id,
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
          direction: FriendRequestDirection.outgoing,
          requestedAt: DateTime(2026),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text(l10n.viewedProfileRequestSent), findsOneWidget);
      final previous = find.text(l10n.viewedProfileAddFriend);
      expect(previous, findsOneWidget);
      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(of: previous, matching: find.byType(IgnorePointer)),
            )
            .any((p) => p.ignoring),
        isTrue,
      );
      expect(tester.getRect(find.byType(ProfilePhotoHero)), initial);
      await tester.pumpAndSettle();
      expect(find.text(l10n.viewedProfileAddFriend), findsNothing);
      f.friends.distance.complete(
        UserDistance(
          value: 3,
          unit: DistanceUnit.kilometers,
          updatedAt: DateTime(2026),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.text(l10n.viewedProfileDistanceKilometers(3)),
        findsOneWidget,
      );
      expect(find.text('???'), findsOneWidget);
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('profile-metadata-reveal')),
            )
            .opacity
            .value,
        1,
      );
      await tester.pumpAndSettle();
      expect(find.text('???'), findsNothing);
      expect(tester.getRect(find.byType(ProfilePhotoHero)), initial);
      expect(f.friends.sendCalls, 0);
      expect(f.profiles.reads, 1);
      expect(f.friends.distanceReads, 1);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  testWidgets(
    'reduced motion settles immediately and closing during reveal disposes its ticker',
    (tester) async {
      final f = await _mount(tester, reduced: true);
      f.profiles.ready.complete(f.value);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('profile-metadata-reveal')),
            )
            .opacity
            .value,
        1,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await f.close(tester);
      final second = await _mount(tester);
      second.profiles.ready.complete(second.value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await second.close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}

int _nextId = 0;

Future<_Fixture> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool snapshot = true,
  bool reduced = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final id = 'loading-peer-${_nextId++}';
  final photo = ProfilePhoto(
    position: 0,
    storagePath: '$id/photo.png',
    bytes: File('assets/logo/logo_yap_chat.png').readAsBytesSync(),
  );
  final value = ViewedProfile(
    profile: UserProfile(
      id: id,
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
  );
  final profiles = _Profiles(preferences);
  final friends = _Friends();
  final blocks = MockBlocklistRepository();
  final f = _Fixture(id, value, profiles, friends);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IProfileRepository>.value(value: profiles),
        RepositoryProvider<IFriendsRepository>.value(value: friends),
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
            create: (_) => PresenceCubit(repository: MockPresenceRepository()),
          ),
          BlocProvider(create: (_) => BlocklistCubit(repository: blocks)),
        ],
        child: MaterialApp(
          navigatorKey: f.navigator,
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: snapshot
                ? Center(
                    child: ProfileAvatarHero(
                      profileId: id,
                      avatarStoragePath: photo.storagePath,
                      child: UserAvatar(
                        avatarRevision: photo.storagePath,
                        initialAvatarPath: File(
                          'assets/logo/logo_yap_chat.png',
                        ).absolute.path,
                        size: 54,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  f.navigator.currentState!.push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ViewedProfilePage(userId: id),
    ),
  );
  await tester.pump();
  friends.rows.add([]);
  friends.requests.add([]);
  await tester.pump();
  return f;
}

class _Fixture {
  _Fixture(this.id, this.value, this.profiles, this.friends);
  final String id;
  final ViewedProfile value;
  final _Profiles profiles;
  final _Friends friends;
  final navigator = GlobalKey<NavigatorState>();
  Future<void> close(WidgetTester tester) async {
    if (!profiles.ready.isCompleted) profiles.ready.complete(value);
    if (!friends.distance.isCompleted) friends.distance.complete(null);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => Future.wait([friends.rows.close(), friends.requests.close()]),
    );
  }
}

class _Profiles extends MockProfileRepository {
  _Profiles(SharedPreferences preferences) : super(preferences: preferences);
  final ready = Completer<ViewedProfile>();
  int reads = 0;
  @override
  Future<ViewedProfile?> getCachedViewedProfile(String userId) async => null;
  @override
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) {
    reads++;
    return ready.future;
  }
}

class _Friends extends MockFriendsRepository {
  final rows = StreamController<List<Friend>>.broadcast(sync: true);
  final requests = StreamController<List<FriendRequest>>.broadcast(sync: true);
  final distance = Completer<UserDistance?>();
  int distanceReads = 0, sendCalls = 0;
  @override
  Stream<List<Friend>> watchPaginatedFriends() => rows.stream;
  @override
  Stream<List<FriendRequest>> watchRequests() => requests.stream;
  @override
  Future<UserDistance?> getUserDistance(String userId) {
    distanceReads++;
    return distance.future;
  }

  @override
  Future<void> sendRequest(FriendCandidate candidate) async {
    sendCalls++;
  }
}
