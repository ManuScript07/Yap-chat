// Opt-in: persistent local fixture + production repositories + on-disk Drift.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

const _enabled = bool.fromEnvironment('PAGINATION_LAB_CACHE_TEST');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'persistent fixture loads real pages and preserves lists/search in offline caches',
    () async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = _RealHttp();
      addTearDown(() => HttpOverrides.global = previousHttp);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (_) async => null,
          );
      final state =
          jsonDecode(
                File(
                  '.local/pagination-lab/manual/state.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final launch =
          jsonDecode(
                File(
                  '.local/pagination-lab/manual/launch.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final owner = (state['owner'] as Map)['id'] as String;
      final hub = (state['hub'] as Map)['id'] as String;
      final url = Uri.parse(launch['PAGINATION_LAB_URL'] as String);
      expect(url.host, '127.0.0.1');
      expect(url.scheme, 'http');
      final directory = Directory('.local/pagination-lab/cache-test-$pid')
        ..createSync(recursive: true);
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.absolute.path);
      addTearDown(() => PathProviderPlatform.instance = paths);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final transport = _Transport();
      final client = SupabaseClient(
        url.toString(),
        launch['PAGINATION_LAB_KEY'] as String,
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.setSession(
        launch['PAGINATION_LAB_REFRESH_TOKEN'] as String,
      );
      expect(client.auth.currentUser?.id, owner);
      final account = AccountSessionController(initialUserId: owner);
      final talker = Talker(settings: TalkerSettings(enabled: false));
      AppDatabase database = AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/cache.sqlite')),
      );
      RepositoryContainer create() => RepositoryContainer.prod(
        config: AppConfig(
          environment: AppEnvironment.local,
          preferences: preferences,
          talker: talker,
          env: const {},
          database: database,
          accountSessionController: account,
          supabaseClient: client,
        ),
      );
      var repositories = create();
      final subscriptions = <StreamSubscription<dynamic>>[];
      final report = <String, Object?>{};
      report['owner'] = owner;
      Future<void> stop() async {
        for (final s in subscriptions) {
          await s.cancel();
        }
        subscriptions.clear();
        await repositories.chatsRepository.pauseRealtime();
        await repositories.friendsRepository.pauseRealtime();
        repositories.mediaCache.dispose();
      }

      try {
        final list = repositories.chatsRepository as IChatsListRepository;
        var view = const ChatListViewState();
        subscriptions.add(list.watchChatList().listen((v) => view = v));
        await _until(
          () =>
              view.chats.length >= 50 &&
              !view.isLoadingRemote &&
              !view.isRefreshing,
        );
        expect(view.chats.any((c) => c.userName == 'Глубокий чат Лаб'), false);
        await list.setChatListQuery('Глубокий чат Лаб');
        await _until(
          () =>
              view.query.toLowerCase() == 'глубокий чат лаб' &&
              view.chats.any((c) => c.userName == 'Глубокий чат Лаб'),
        );
        await list.setChatListQuery('');
        await _until(
          () =>
              view.query.isEmpty &&
              view.ready &&
              !view.isRefreshing &&
              !view.isLoadingRemote &&
              !view.isLoadingCache &&
              view.hasMore,
        );
        for (var i = 0; i < 20 && view.hasMore; i++) {
          await list.loadMoreChatList();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(view.hasMore, false);
        expect(view.chats.length, 220);
        expect(view.chats.map((c) => c.id).toSet().length, 220);
        report['chatsCached'] = view.chats.length;
        final friends = repositories.friendsRepository;
        final requests = await friends.getRequests();
        expect(requests.length, 120);
        final searched = await friends.searchUsers('Дальний друг Лаб');
        expect(searched.any((f) => f.displayName == 'Дальний друг Лаб'), true);
        expect(
          (await friends.watchCachedFriends().first).any(
            (f) => f.displayName == 'Дальний друг Лаб',
          ),
          true,
        );
        for (var i = 0; i < 8; i++) {
          if ((await friends.watchCachedFriends().first).length >= 160) break;
          await friends.loadMoreFriends();
        }
        final friendCount = (await friends.watchCachedFriends().first).length;
        report['friendsCached'] = friendCount;
        if (friendCount != 160) {
          report['friendPaginationIssue'] = {
            'expected': 160,
            'actual': friendCount,
            'wireCursors': transport.friendCursors,
          };
        }
        report['requestsCached'] = requests.length;
        final profile = repositories.profileRepository;
        await profile.refreshViewedProfileFriends(hub);
        var snapshot = await profile.getCachedViewedProfileFriendsSnapshot(hub);
        for (var i = 0; i < 12 && snapshot!.hasMore; i++) {
          snapshot = await profile.loadMoreViewedProfileFriends(hub);
        }
        expect(snapshot!.friends.length, 240);
        expect(snapshot.hasMore, false);
        expect(
          snapshot.friends.any(
            (f) => f.displayName == 'Последний друг профиля Лаб',
          ),
          true,
        );
        report['profileFriendsCached'] = snapshot.friends.length;
        final nearby = repositories.nearbyRepository;
        const filters = NearbyFilters();
        var feed = await nearby.refreshFeed(filters);
        for (var i = 0; i < 5 && feed.hasMore; i++) {
          feed = (await nearby.loadMore(filters))!;
        }
        expect(feed.people.length, 100);
        expect(feed.hasMore, false);
        final withAvatar = feed.people.firstWhere(
          (p) => p.avatarStoragePath != null,
        );
        final avatar = await nearby.resolveAvatar(withAvatar);
        expect(avatar, isNotNull);
        expect(await File(avatar!).exists(), true);
        report['nearbyCached'] = feed.people.length;
        report['privateAvatarDownloaded'] = true;
        await stop();
        await database.close();
        transport.offline = true;
        database = AppDatabase.forTesting(
          NativeDatabase(File('${directory.path}/cache.sqlite')),
        );
        repositories = create();
        expect(
          (await repositories.friendsRepository.watchCachedFriends().first)
              .length,
          friendCount,
        );
        expect(
          (await repositories.friendsRepository.watchCachedRequests().first)
              .length,
          120,
        );
        expect(
          (await repositories.profileRepository
                  .getCachedViewedProfileFriendsSnapshot(hub))!
              .friends
              .length,
          240,
        );
        expect(
          (await repositories.nearbyRepository.getCachedFeed(
            filters,
          ))!.people.length,
          100,
        );
        final restored = repositories.chatsRepository as IChatsListRepository;
        var restoredView = const ChatListViewState();
        subscriptions.add(
          restored.watchChatList().listen((v) => restoredView = v),
        );
        await _until(() => restoredView.ready && restoredView.chats.isNotEmpty);
        for (var i = 0; i < 10 && restoredView.hasMoreCached; i++) {
          await restored.loadMoreChatList();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect(restoredView.chats.length, 220);
        await restored.setChatListQuery('Глубокий чат Лаб');
        await _until(
          () => restoredView.chats.any((c) => c.userName == 'Глубокий чат Лаб'),
        );
        report['offlineAfterDatabaseReopen'] = true;
        report['onlineRequests'] = transport.onlineRequests;
        File(
          '.local/pagination-lab/manual/cache-verification.json',
        ).writeAsStringSync(jsonEncode(report));
        // ignore: avoid_print
        print('PAGINATION_LAB_CACHE ${jsonEncode(report)}');
        expect(
          report['friendPaginationIssue'],
          isNull,
          reason:
              'Every server friend must survive cursor pagination; see cache-verification.json',
        );
      } finally {
        await stop();
        await client.dispose();
        await database.close();
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _until(bool Function() test) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('Local pagination state did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Transport extends http.BaseClient {
  final _client = http.Client();
  bool offline = false;
  int onlineRequests = 0;
  final friendCursors = <Object?>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) {
      throw const SocketException('Fixture transport deliberately offline');
    }
    onlineRequests++;
    if (request.url.path.endsWith('/get_friends_page') &&
        request is http.Request) {
      friendCursors.add(jsonDecode(request.body));
    }
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}

class _RealHttp extends HttpOverrides {}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationCachePath() async => path;
}
