import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  for (final language in ['ru', 'en']) {
    testWidgets('$language actual profile draft mute shows limit and can retry', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final chats = _Chats();
      final profiles = _Profiles(preferences);
      final friends = _Friends();
      final location = _Location(preferences);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<IProfileRepository>.value(value: profiles),
            RepositoryProvider<IFriendsRepository>.value(value: friends),
            RepositoryProvider<IChatsRepository>.value(value: chats),
            RepositoryProvider<ILocationRepository>.value(value: location),
            RepositoryProvider<ISettingsRepository>.value(
              value: MockSettingsRepository(),
            ),
            RepositoryProvider<IBlocklistRepository>.value(
              value: MockBlocklistRepository(),
            ),
            RepositoryProvider<IUserReportsRepository>.value(
              value: const MockUserReportsRepository(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    PresenceCubit(repository: MockPresenceRepository()),
              ),
              BlocProvider(
                create: (context) => BlocklistCubit(
                  repository: context.read<IBlocklistRepository>(),
                ),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                fontFamily: 'Roboto',
              ),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ViewedProfilePage(userId: 'friend-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byIcon(Icons.settings_rounded));
      final cubit = context.read<ViewedProfileCubit>();
      final l10n = AppLocalizations.of(context)!;
      expect(cubit.state.viewedProfile!.isFriend, isTrue);
      expect(cubit.state.chat!.isDraft, isTrue);
      expect(cubit.state.chat!.isMuted, isFalse);
      expect(chats.creationPeers, isEmpty);
      expect(chats.muteWrites, isEmpty);
      expect(chats.unexpectedCalls, isEmpty);

      final initialReads = (
        profiles.reads,
        friends.locationReads,
        friends.distanceReads,
        location.cachedReads,
        chats.cacheReads,
        chats.prepareReads,
        chats.peerWatches,
      );
      void expectNoExtraReads() {
        expect((
          profiles.reads,
          friends.locationReads,
          friends.distanceReads,
          location.cachedReads,
          chats.cacheReads,
          chats.prepareReads,
          chats.peerWatches,
        ), initialReads);
        expect(chats.unexpectedCalls, isEmpty);
      }

      for (var attempt = 1; attempt <= 2; attempt++) {
        await tester.tap(find.byIcon(Icons.settings_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(chats.creationPeers, hasLength(attempt - 1));
        final mute = find.text(l10n.viewedProfileMute.toLowerCase());
        expect(mute, findsOneWidget);
        await tester.tap(mute);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l10n.chatsLimitTitle), findsOneWidget);
        expect(find.text(l10n.chatsLimitContent(100)), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(chats.creationPeers, List.filled(attempt, 'friend-1'));
        expect(chats.muteWrites, isEmpty);
        expect(cubit.state.chat!.isDraft, isTrue);
        expect(cubit.state.chat!.isMuted, isFalse);
        expect(cubit.state.isActionPending, isFalse);
        expect(cubit.state.actionError, isNull);
        expectNoExtraReads();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(l10n.chatsLimitDismiss));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        // Let any unintended retry/preflight scheduled by dismissal surface.
        await tester.pump(const Duration(seconds: 1));
        expect(chats.creationPeers, hasLength(attempt));
        expectNoExtraReads();
      }

      // Prove the action is usable after refusals, including a real success.
      chats.atLimit = false;
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.viewedProfileMute.toLowerCase()));
      await tester.pumpAndSettle();
      expect(chats.creationPeers, List.filled(3, 'friend-1'));
      expect(chats.muteWrites, hasLength(1));
      expect(chats.muteWrites.single.$1, {'direct-friend-1'});
      expect(chats.muteWrites.single.$2, isTrue);
      expect(cubit.state.chat!.isDraft, isFalse);
      expect(cubit.state.chat!.isMuted, isTrue);
      expect(cubit.state.isActionPending, isFalse);
      expect(cubit.state.actionError, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expectNoExtraReads();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(find.text(l10n.viewedProfileUnmute.toLowerCase()), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Dispose the actual page and its providers before test fixture teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

class _Chats extends MockChatsRepository implements IChatsPeerRepository {
  final creationPeers = <String>[];
  final muteWrites = <(Set<String>, bool)>[];
  final unexpectedCalls = <String>[];
  bool atLimit = true;
  int cacheReads = 0;
  int prepareReads = 0;
  int peerWatches = 0;

  final draft = Chat.directDraft(
    peerId: 'friend-1',
    peerUsername: 'masha',
    peerDisplayName: 'Маша',
  );

  @override
  Stream<Chat?> watchChatByPeerId(String peerId) {
    peerWatches++;
    return Stream<Chat?>.value(null);
  }

  @override
  Future<Chat?> getCachedChatByPeerId(String peerId) async {
    cacheReads++;
    return null;
  }

  @override
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) async {
    prepareReads++;
    return draft;
  }

  @override
  Future<Chat> ensureDirectChat(String peerId) async {
    creationPeers.add(peerId);
    if (atLimit) throw const ChatLimitReachedException();
    return draft.copyWith(id: 'direct-friend-1');
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    muteWrites.add((Set.of(ids), isMuted));
  }

  @override
  Stream<List<Chat>> watchChats() {
    unexpectedCalls.add('watchChats');
    return const Stream.empty();
  }

  @override
  Future<List<Chat>> getChats() async {
    unexpectedCalls.add('getChats');
    return [];
  }

  @override
  Future<Chat?> getChatById(String chatId) async {
    unexpectedCalls.add('getChatById');
    return null;
  }

  @override
  Stream<Chat?> watchChat(String chatId) {
    unexpectedCalls.add('watchChat');
    return const Stream.empty();
  }

  @override
  Future<void> resumeRealtime() async {
    unexpectedCalls.add('resumeRealtime');
  }
}

class _Profiles extends MockProfileRepository {
  _Profiles(SharedPreferences preferences) : super(preferences: preferences);

  int reads = 0;

  @override
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) async {
    reads++;
    final profile = await super.getViewedProfile(
      userId,
      registerView: registerView,
    );
    return profile.copyWith(relationship: ProfileRelationship.friend);
  }
}

class _Friends extends MockFriendsRepository {
  _Friends() : super(includeSampleFriends: true);

  int locationReads = 0;
  int distanceReads = 0;

  @override
  Future<FriendLocationLookup> getFriendLocation(String friendId) {
    locationReads++;
    return super.getFriendLocation(friendId);
  }

  @override
  Future<UserDistance?> getUserDistance(String userId) {
    distanceReads++;
    return super.getUserDistance(userId);
  }
}

class _Location extends LocationRepository {
  _Location(SharedPreferences preferences) : super(preferences: preferences);

  int cachedReads = 0;

  @override
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    cachedReads++;
    // Supporting profile distance calculation must not invoke device GPS.
    return CachedTrackedLocation(
      latitude: 55.75,
      longitude: 37.61,
      updatedAt: DateTime(2026, 10, 27),
    );
  }
}
