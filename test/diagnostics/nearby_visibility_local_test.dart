import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Auth and PostgREST enforce the nearby visibility contract',
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
              as Map;
      final launch =
          jsonDecode(
                File(
                  '.local/pagination-lab/manual/launch.json',
                ).readAsStringSync(),
              )
              as Map;
      final url = Uri.parse(launch['PAGINATION_LAB_URL'] as String);
      expect(url.host, '127.0.0.1');
      final actor = (state['users'] as List).cast<Map>().firstWhere(
        (u) => u['index'] == 13,
      );
      final client = SupabaseClient(
        url.toString(),
        launch['PAGINATION_LAB_KEY'] as String,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: actor['email'] as String,
        password: state['password'] as String,
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepository(
        cache: SettingsCacheDataSource(database: db),
        remote: SettingsRemoteDataSource(client: client),
        accountSessionController: AccountSessionController(
          initialUserId: client.auth.currentUser!.id,
        ),
      );
      final original = await repo.refreshSearchPrivacySettings();
      try {
        final hidden = await repo.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          false,
        );
        expect(hidden.nearbyVisible, isFalse);
        expect(
          (await repo.readCachedSearchPrivacySettings())!.nearbyVisible,
          isFalse,
        );
        await expectLater(
          client.rpc('get_nearby_people'),
          throwsA(
            isA<PostgrestException>().having(
              (e) => e.message,
              'error',
              contains('nearby_visibility_disabled'),
            ),
          ),
        );
        final enabled = await repo.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          true,
        );
        expect(enabled, original.copyWith(nearbyVisible: true));
        expect(
          (await repo.refreshSearchPrivacySettings()).nearbyVisible,
          isTrue,
        );
      } finally {
        await repo.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          original.nearbyVisible,
        );
      }
      expect(client.realtime.channels, isEmpty);
    },
    skip: !const bool.fromEnvironment('PAGINATION_LAB_CACHE_TEST'),
  );
}

class _RealHttp extends HttpOverrides {}
