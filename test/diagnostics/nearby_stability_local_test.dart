// Opt-in: real local GoTrue and nearby RPC; no relationships or messages changed.
import 'dart:async';
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
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';

const _enabled = bool.fromEnvironment('PAGINATION_LAB_CACHE_TEST');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real nearby pages are bounded and a late page cannot replace a refreshed feed',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _RealHttp();
      addTearDown(() => HttpOverrides.global = previous);
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
      expect(state['marker'], 'yap-pagination-lab-v1');
      final url = Uri.parse(launch['PAGINATION_LAB_URL'] as String);
      expect(url.scheme, 'http');
      expect(url.host, '127.0.0.1');
      // Separate normal fixture actor avoids consuming the manual owner's quota.
      final actor = (state['users'] as List).cast<Map>().firstWhere(
        (u) => u['index'] == 12,
      );
      expect((actor['email'] as String).endsWith('@example.test'), true);
      final transport = _Transport();
      final client = SupabaseClient(
        url.toString(),
        launch['PAGINATION_LAB_KEY'] as String,
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: actor['email'] as String,
        password: state['password'] as String,
      );
      final owner = client.auth.currentUser!.id;
      expect(owner, actor['id']);
      SharedPreferences.setMockInitialValues({});
      var preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = AccountSessionController(initialUserId: owner);
      final media = MediaCacheService(database: database);
      addTearDown(media.dispose);
      NearbyRepository repository() => NearbyRepository(
        cache: NearbyCacheDataSource(
          preferences: preferences,
          environment: 'local-stability',
        ),
        remote: NearbyRemoteDataSource(client: client),
        mediaCache: media,
        accountSessionController: account,
        config: AppConfig(
          environment: AppEnvironment.local,
          preferences: preferences,
          talker: Talker(),
          env: const {},
          database: database,
          accountSessionController: account,
        ),
      );
      var repo = repository();
      var feed = await repo.refreshFeed(const NearbyFilters());
      final sizes = [feed.people.length];
      while (feed.hasMore) {
        feed = (await repo.loadMore(const NearbyFilters()))!;
        sizes.add(feed.people.length);
        expect(sizes.length, lessThan(6));
      }
      expect(sizes, [30, 60, 90, 120, 150]);
      expect(feed.people.map((p) => p.id).toSet().length, 150);
      expect(feed.people.any((p) => p.id == owner), false);
      final stableIds = feed.people.map((p) => p.id).toList();
      final count = transport.calls.length;
      await repo.loadMore(const NearbyFilters());
      expect(transport.calls.length, count);
      final disk = {
        for (final key in preferences.getKeys())
          key: preferences.getString(key)!,
      };
      SharedPreferences.setMockInitialValues(disk);
      preferences = await SharedPreferences.getInstance();
      repo = repository();
      transport.offline = true;
      expect(
        (await repo.getCachedFeed(
          const NearbyFilters(),
        ))!.people.map((p) => p.id),
        stableIds,
      );
      await repo.loadMore(const NearbyFilters());
      expect(transport.calls.length, count);
      transport.offline = false;
      await repo.refreshFeed(const NearbyFilters());
      transport.holdNextPage = true;
      final old = repo.loadMore(const NearbyFilters());
      final rejected = expectLater(
        old,
        throwsA(isA<NearbyFeedSupersededException>()),
      );
      await transport.held.future;
      final fresh = await repo.refreshFeed(const NearbyFilters());
      transport.release.complete();
      await rejected;
      expect(
        (await repo.getCachedFeed(
          const NearbyFilters(),
        ))!.people.map((p) => p.id),
        fresh.people.map((p) => p.id),
      );
      expect(fresh.people.length, 30);
      expect(transport.calls.length, 8);
      expect(client.getChannels(), isEmpty);
      final report = {
        'actor': owner,
        'sizes': sizes,
        'reads': transport.calls.length,
        'offlineSnapshot': true,
        'stalePageRejected': true,
        'afterRace': fresh.people.length,
        'realtimeChannels': 0,
      };
      File(
        '.local/pagination-lab/manual/nearby-stability-verification.json',
      ).writeAsStringSync(jsonEncode(report));
      // ignore: avoid_print
      print('NEARBY_STABILITY_LOCAL ${jsonEncode(report)}');
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _Transport extends http.BaseClient {
  final _client = http.Client();
  final calls = <Object?>[];
  bool offline = false, holdNextPage = false;
  final held = Completer<void>(), release = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('Deliberately offline');
    bool hold = false;
    if (request.url.path.endsWith('/get_nearby_people') &&
        request is http.Request) {
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(params);
      hold = holdNextPage && params['after_user_id'] != null;
      if (hold) holdNextPage = false;
    }
    final response = await _client.send(request);
    if (hold) {
      held.complete();
      await release.future;
    }
    return response;
  }

  @override
  void close() {
    if (!release.isCompleted) release.complete();
    _client.close();
  }
}

class _RealHttp extends HttpOverrides {}
