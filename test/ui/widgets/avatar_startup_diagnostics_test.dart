// Offline startup regressions using real persisted metadata and media files.
// No backend/network is configured.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/cached_avatar_frames.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/chats/widgets/chat_list_item.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/friend_list_item.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_remote_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_repository.dart';
import 'package:yap_chat/repositories/friends/contact_match_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_remote_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_repository.dart';
import 'package:yap_chat/repositories/presence/mock_presence_repository.dart';
import 'package:yap_chat/ui/theme/theme.dart';
import 'package:yap_chat/ui/widgets/user_avatar.dart';

void main() {
  setUpAll(() {
    // Typography is not under test; avoid unrelated runtime font downloads.
    AppTextStyles.chatName = const TextStyle(fontSize: 18);
    AppTextStyles.messagePreview = const TextStyle(fontSize: 16);
    AppTextStyles.metadata = const TextStyle(fontSize: 14);
    AppTextStyles.badgeText = const TextStyle(fontSize: 14);
  });

  for (final ratio in [1.0, 3.0]) {
    for (final kind in ['chat', 'friend']) {
      testWidgets(
        '$kind at ${ratio}x: cold start paints the cached photo in the first visible frame',
        (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixture = await tester.runAsync(
            () => _OfflineFixture.create(kind),
          );
          final data = fixture!;
          addTearDown(data.dispose);
          final presence = PresenceCubit(repository: MockPresenceRepository());
          addTearDown(presence.close);

          var loaderCalls = 0;
          Widget page() => _host(
            RepositoryProvider<AccountSessionController>.value(
              value: data.account,
              child: data.tile(() {
                loaderCalls++;
                return data.resolve();
              }),
            ),
            presence,
          );

          expect(File(data.avatarPath).existsSync(), isTrue);
          expect(data.cachedChat.avatarUrl, isNull);
          expect(data.cachedFriend.avatarUrl, isNull);
          expect(data.cachedChat.avatarStoragePath, data.storagePath);
          expect(data.cachedFriend.avatarStoragePath, data.storagePath);
          expect(data.cachedChat.cachedAvatarPath, data.avatarPath);
          expect(data.cachedFriend.cachedAvatarPath, data.avatarPath);

          tester.binding.imageCache.clear();
          tester.binding.imageCache.clearLiveImages();
          await tester.runAsync(
            () =>
                CachedAvatarFrames(
                  database: data.database,
                  mediaCache: data.media,
                ).prepare(
                  ownerUserId: data.account.userId!,
                  devicePixelRatio: tester.view.devicePixelRatio,
                  viewportHeight:
                      tester.view.physicalSize.height /
                      tester.view.devicePixelRatio,
                  isCurrent: () => true,
                ),
          );
          await tester.pumpWidget(page());
          expect(loaderCalls, 0);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(Image), findsOneWidget);
          final image = tester.widget<Image>(find.byType(Image));
          expect(_fileProvider(image).file.path, data.avatarPath);
          expect(
            find.byIcon(Icons.person),
            findsNothing,
            reason:
                'A cached photo must be painted in the first visible frame, '
                'not replace a placeholder after disk decoding.',
          );
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            isNotNull,
          );
          expect(find.byIcon(Icons.person), findsNothing);
          expect(find.byType(AnimatedOpacity), findsNothing);
          expect(
            loaderCalls,
            0,
            reason: 'Cached files must bypass lazy/network loading.',
          );

          await _waitForDecodedFrame(tester);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpWidget(page());
          expect(loaderCalls, 0);
          expect(find.byIcon(Icons.person), findsNothing);

          // A remount within the same process can use the widget's static path
          // map and Flutter's decoded ImageCache, unlike a fresh app process.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(page());
          expect(loaderCalls, 0);
          expect(find.byIcon(Icons.person), findsNothing);
          expect(find.byType(Image), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'an existing local file is painted immediately after decode without a fade',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'yap-avatar-decode-',
      );
      final file = File(
        'assets/logo/logo_yap_chat.png',
      ).copySync('${directory.path}/avatar.png');
      addTearDown(() => directory.deleteSync(recursive: true));
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UserAvatar(avatarUrl: file.path)),
        ),
      );
      expect(find.byIcon(Icons.person), findsOneWidget);
      await _waitForDecodedFrame(tester);
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'remembered file path does not retain decoded image after eviction',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'yap-avatar-eviction-',
      );
      final file = File(
        'assets/logo/logo_yap_chat.png',
      ).copySync('${directory.path}/avatar.png');
      addTearDown(() => directory.deleteSync(recursive: true));
      var loads = 0;
      Widget page() => MaterialApp(
        home: Scaffold(
          body: UserAvatar(
            avatarRevision: 'eviction:${directory.path}',
            avatarLoader: () async {
              loads++;
              return file.path;
            },
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      await _waitForDecodedFrame(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();

      await tester.pumpWidget(page());
      expect(
        loads,
        1,
        reason: 'The resolved path survives inside this process.',
      );
      expect(find.byIcon(Icons.person), findsOneWidget);
      await _waitForDecodedFrame(tester);
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

FileImage _fileProvider(Image image) =>
    (image.image as ResizeImage).imageProvider as FileImage;

Future<void> _waitForDecodedFrame(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null)) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  fail('The existing offline avatar did not decode.');
}

Widget _host(Widget tile, PresenceCubit presence) => BlocProvider.value(
  value: presence,
  child: MaterialApp(
    theme: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandPrimary,
        onSurface: AppColors.textPrimary,
      ),
    ),
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: tile),
  ),
);

class _OfflineFixture {
  _OfflineFixture(this.kind, this.directory);
  final String kind;
  final Directory directory;
  late final Directory cacheDirectory;
  late final AppDatabase database;
  late final MediaCacheService media;
  late final AccountSessionController account;
  late final Chat cachedChat;
  late final Friend cachedFriend;
  late final String avatarPath;
  late final String storagePath;
  late final ChatsRepository chats;
  late final FriendsRepository friends;

  static Future<_OfflineFixture> create(String kind) async {
    final data = _OfflineFixture(
      kind,
      await Directory.systemTemp.createTemp('yap-avatar-startup-'),
    );
    data.cacheDirectory = Directory('${data.directory.path}/cache');
    data.storagePath = 'peer/${data.directory.path.hashCode}/avatar.png';
    const owner = 'offline-owner';
    final dbFile = File('${data.directory.path}/cache.sqlite');
    var database = AppDatabase.forTesting(NativeDatabase(dbFile));
    final chat = Chat(
      id: 'chat',
      peerId: 'peer',
      userName: 'Peer',
      avatarStoragePath: data.storagePath,
      lastMessage: 'Message',
      lastMessageTime: DateTime.utc(2026, 10, 18),
      unreadCount: 0,
      isOnline: false,
      isLastMessageFromMe: false,
    );
    final friend = Friend(
      id: 'peer',
      username: 'peer',
      displayName: 'Peer',
      avatarStoragePath: data.storagePath,
      friendsSince: DateTime.utc(2026, 10, 18),
    );
    await ChatsCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    ).replaceAll([chat]);
    await FriendsCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    ).replaceAll(friends: [friend], requests: const []);
    final seed = MediaCacheService(
      database: database,
      environment: 'test',
      cacheDirectoryProvider: () async => data.cacheDirectory,
      supportDirectoryProvider: () async => data.directory,
    );
    data.avatarPath = await seed.storeBytes(
      ownerUserId: owner,
      bucket: 'avatars',
      storagePath: data.storagePath,
      bytes: await File('assets/logo/logo_yap_chat.png').readAsBytes(),
    );
    seed.dispose();
    await database.close();

    // Reopen real persisted metadata with a new service and cold path maps.
    database = AppDatabase.forTesting(NativeDatabase(dbFile));
    data.database = database;
    data.media = MediaCacheService(
      database: database,
      environment: 'test',
      cacheDirectoryProvider: () async => data.cacheDirectory,
      supportDirectoryProvider: () async => data.directory,
    );
    final chatCache = ChatsCacheDataSource(
      database: database,
      mediaCache: data.media,
      userIdProvider: () => owner,
    );
    final friendCache = FriendsCacheDataSource(
      database: database,
      mediaCache: data.media,
      userIdProvider: () => owner,
    );
    data.cachedChat = (await chatCache.read()).single;
    data.cachedFriend = (await friendCache.readFriends()).single;
    SharedPreferences.setMockInitialValues({});
    final account = AccountSessionController()..setAuthenticatedUser(owner);
    data.account = account;
    final config = AppConfig(
      environment: AppEnvironment.local,
      preferences: await SharedPreferences.getInstance(),
      talker: Talker(),
      env: const {},
      database: database,
      accountSessionController: account,
    );
    data.chats = ChatsRepository(
      config: config,
      cache: chatCache,
      remote: _UnusedChatsRemote(),
      mediaCache: data.media,
      chatCache: ChatCacheDataSource(
        database: database,
        userIdProvider: () => owner,
      ),
      conversationSync: _UnusedConversationSync(),
      accountSessionController: account,
    );
    data.friends = FriendsRepository(
      config: config,
      cache: friendCache,
      contactMatchCache: _UnusedContactCache(),
      remote: _UnusedFriendsRemote(),
      mediaCache: data.media,
      accountSessionController: account,
    );
    return data;
  }

  Future<String?> resolve() => kind == 'chat'
      ? chats.resolveAvatar(cachedChat)
      : friends.resolveFriendAvatar(cachedFriend);

  Widget tile(Future<String?> Function() loader) => kind == 'chat'
      ? ChatListItem(chat: cachedChat, avatarLoader: loader)
      : FriendListItem(
          friend: cachedFriend,
          avatarLoader: loader,
          onChat: () {},
          onLocation: () {},
        );

  Future<void> dispose() async {
    media.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _UnusedChatsRemote implements ChatsRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected remote access: $invocation');
}

class _UnusedFriendsRemote implements FriendsRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected remote access: $invocation');
}

class _UnusedConversationSync implements ConversationSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected conversation sync: $invocation');
}

class _UnusedContactCache implements ContactMatchCacheDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected contact lookup: $invocation');
}
