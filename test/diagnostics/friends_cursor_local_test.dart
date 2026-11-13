// Opt-in integration: real local GoTrue/RPC and file-backed production cache.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

const _enabled = bool.fromEnvironment('PAGINATION_LAB_CACHE_TEST');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real friend pages retain exact order and repair an old incomplete cache',
    () async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = _RealHttp();
      addTearDown(() => HttpOverrides.global = previousHttp);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final launch =
          jsonDecode(
                File(
                  '.local/pagination-lab/manual/launch.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final url = Uri.parse(launch['PAGINATION_LAB_URL'] as String);
      expect(url.host, '127.0.0.1');
      expect(url.scheme, 'http');
      final transport = _Transport();
      final client = SupabaseClient(
        url.toString(),
        launch['PAGINATION_LAB_KEY'] as String,
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.setSession(
        launch['PAGINATION_LAB_REFRESH_TOKEN'] as String,
      );
      final owner = client.auth.currentUser!.id;
      expect(owner, launch['PAGINATION_LAB_OWNER_ID']);
      final account = AccountSessionController(initialUserId: owner);
      final talker = Talker(settings: TalkerSettings(enabled: false));
      final remote = FriendsRemoteDataSource(client: client, talker: talker);
      final expected = <Friend>[];
      FriendPageCursor? cursor;
      do {
        final page = await remote.fetchFriendsPage(after: cursor);
        expected.addAll(page.friends);
        cursor = page.nextCursor;
        expect(expected.length, lessThan(2000));
      } while (cursor != null);
      expect(expected.length, greaterThan(100));
      expect(expected.map((f) => f.id).toSet().length, expected.length);
      expect(
        expected.any(
          (f) => f.friendsSince.microsecondsSinceEpoch % 1000000 != 0,
        ),
        true,
      );
      final report = <String, Object?>{
        'owner': owner,
        'serverFriends': expected.length,
      };
      for (final legacy in [false, true]) {
        final directory = Directory(
          '.local/pagination-lab/friend-cursor-$pid-${legacy ? 'legacy' : 'fresh'}-${DateTime.now().microsecondsSinceEpoch}',
        )..createSync(recursive: true);
        final file = File('${directory.path}/cache.sqlite');
        var database = AppDatabase.forTesting(NativeDatabase(file));
        FriendsCacheDataSource cache() => FriendsCacheDataSource(
          database: database,
          userIdProvider: () => owner,
        );
        final dropped = {48, 49, 98, 99, 148, 149};
        if (legacy) {
          await cache().replaceAll(
            friends: [
              for (final entry in expected.indexed)
                if (!dropped.contains(entry.$1)) entry.$2,
            ],
            requests: const [],
            markFriendsComplete: true,
          );
          await database.customStatement(
            'UPDATE cached_friend_list_states SET total_count=?',
            [expected.length],
          );
          await database.customStatement(
            'ALTER TABLE cached_friends DROP COLUMN friends_since_micros',
          );
          await database.customStatement(
            'ALTER TABLE cached_friend_list_states DROP COLUMN next_friends_since_micros',
          );
          await database.customStatement(
            'ALTER TABLE cached_friend_list_states DROP COLUMN requires_cursor_repair',
          );
          await database.customStatement('PRAGMA user_version=28');
          await database.close();
          database = AppDatabase.forTesting(NativeDatabase(file));
          expect(
            (await cache().readFriends()).length,
            expected.length - dropped.length,
          );
          expect(
            (await cache().readFriendListState()).requiresCursorRepair,
            true,
          );
        }
        MediaCacheService? media;
        FriendsRepository repository() {
          media?.dispose();
          media = MediaCacheService(database: database);
          return FriendsRepository(
            config: AppConfig(
              environment: AppEnvironment.local,
              preferences: preferences,
              talker: talker,
              env: const {},
              database: database,
              accountSessionController: account,
              supabaseClient: client,
            ),
            cache: cache(),
            contactMatchCache: ContactMatchCacheDataSource(
              database: database,
              userIdProvider: () => owner,
              keyService: const _Keys(),
            ),
            remote: remote,
            mediaCache: media!,
            accountSessionController: account,
          );
        }

        var repo = repository();
        final pageStart = transport.friendCursors.length;
        try {
          if (legacy) {
            transport.offline = true;
            await expectLater(repo.loadMoreFriends(), throwsA(anything));
            expect(
              (await cache().readFriends()).length,
              expected.length - dropped.length,
            );
            expect(
              (await cache().readFriendListState()).requiresCursorRepair,
              true,
            );
            transport.offline = false;
            await repo
                .loadMoreFriends(); // The missing exact cursor starts at head.
            await repo.loadMoreFriends();
            final checkpoint =
                (await cache().readFriendListState()).nextCursor!;
            await database.close();
            database = AppDatabase.forTesting(NativeDatabase(file));
            repo = repository();
            final restored = await cache().readFriendListState();
            expect(restored.requiresCursorRepair, true);
            expect(restored.nextCursor!.friendId, checkpoint.friendId);
            expect(restored.nextCursor!.friendsSince, checkpoint.friendsSince);
          } else {
            await repo.getRequests();
            final before = (await cache().readFriendListState()).nextCursor!;
            final results = await repo.searchUsers(
              '@${expected.last.username}',
            );
            expect(results.any((f) => f.id == expected.last.id), true);
            final after = (await cache().readFriendListState()).nextCursor!;
            expect(after.friendId, before.friendId);
            expect(after.friendsSince, before.friendsSince);
            transport.offline = true;
            await expectLater(repo.loadMoreFriends(), throwsA(anything));
            final afterFailure =
                (await cache().readFriendListState()).nextCursor!;
            expect(afterFailure.friendId, before.friendId);
            expect(afterFailure.friendsSince, before.friendsSince);
            transport.offline = false;
          }
          var continuations = 0;
          while ((await cache().readFriendListState()).hasMore) {
            await repo.loadMoreFriends();
            expect(++continuations, lessThan(40));
          }
          final actual = await cache().readFriends();
          expect(actual.map((f) => f.id), expected.map((f) => f.id));
          for (var i = 0; i < expected.length; i++) {
            expect(
              actual[i].friendsSince.toUtc(),
              expected[i].friendsSince.toUtc(),
            );
          }
          final complete = await cache().readFriendListState();
          expect(complete.totalCount, expected.length);
          expect(complete.requiresCursorRepair, false);
          final reads = transport.friendCursors.sublist(pageStart);
          expect(reads.length, (expected.length / 50).ceil());
          expect(reads.map(jsonEncode).toSet().length, reads.length);
          final requestCount = transport.onlineRequests;
          await repo.loadMoreFriends();
          expect(transport.onlineRequests, requestCount);
          transport.offline = true;
          await database.close();
          database = AppDatabase.forTesting(NativeDatabase(file));
          repo = repository();
          expect(
            (await repo.watchCachedFriends().first).map((f) => f.id),
            expected.map((f) => f.id),
          );
          expect((await cache().readFriendListState()).hasMore, false);
          expect(transport.onlineRequests, requestCount);
          report[legacy ? 'legacyRecovery' : 'fresh'] = {
            'friends': actual.length,
            'pages': reads.length,
            'offlineReopen': true,
            'exactDates': true,
            'wireCursors': reads,
          };
        } finally {
          transport.offline = false;
          media?.dispose();
          await database.close();
        }
      }
      File(
        '.local/pagination-lab/manual/friend-cursor-verification.json',
      ).writeAsStringSync(jsonEncode(report));
      // ignore: avoid_print
      print('FRIEND_CURSOR_LOCAL ${jsonEncode(report)}');
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _Transport extends http.BaseClient {
  final _client = http.Client();
  final friendCursors = <Object?>[];
  bool offline = false;
  int onlineRequests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Deliberately offline test');
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

class _Keys implements IContactCacheKeyService {
  const _Keys();
  @override
  Future<String> createKey(String normalizedPhone) async => normalizedPhone;
}
