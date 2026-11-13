import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/avatar_storage_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_repository.dart';
import 'package:yap_chat/repositories/profile/viewed_profile_cache_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile reload never restores a deliberately removed Yandex avatar',
    () async {
      const userId = '11111111-1111-4111-8111-111111111111';
      const yandexUrl = 'https://avatars.yandex.net/removed-photo';
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = ProfileCacheDataSource(database: database);
      // Stale bytes/URL may still exist locally when the server reports removal.
      await cache.write(
        UserProfile(
          id: userId,
          username: 'user_name',
          displayName: 'User',
          onboardingCompleted: true,
          avatarUrl: yandexUrl,
          photos: [
            ProfilePhoto(
              position: 0,
              avatarUrl: yandexUrl,
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        ),
      );
      final requests = <String>[];
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/rest/v1/rpc/get_or_create_my_profile') {
            return http.Response(
              jsonEncode([
                {
                  'id': userId,
                  'username': 'user_name',
                  'display_name': 'User',
                  'onboarding_completed': true,
                  'avatar_url': null,
                  'avatar_storage_path': null,
                  'yandex_avatar_disabled': true,
                },
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/rest/v1/profile_photos') {
            return http.Response(
              '[]',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          throw StateError(
            'Unexpected request: ${request.method} ${request.url.path}',
          );
        }),
      );
      addTearDown(client.dispose);
      final storage = _UnusedAvatarStorage();
      final media = _UnusedMediaCache();
      final repository = ProfileRepository(
        client: client,
        cache: cache,
        avatarStorage: storage,
        talker: Talker(),
        accountSessionController: AccountSessionController()
          ..setAuthenticatedUser(userId),
        viewedProfileCache: ViewedProfileCacheDataSource(
          database: database,
          profileCache: cache,
        ),
        mediaCache: media,
      );
      // The OAuth session still carries the original Yandex photo on every login.
      for (var reload = 0; reload < 2; reload++) {
        final profile = await repository.getOrCreateProfile(
          const AuthSession(userId: userId, avatarUrl: yandexUrl),
        );
        final restored = await repository.getCachedProfile(userId);
        for (final actual in [profile, restored!]) {
          expect(actual.yandexAvatarDisabled, isTrue);
          expect(actual.effectivePhotos, isEmpty);
          expect(actual.avatarUrl, isNull);
          expect(actual.avatarStoragePath, isNull);
          expect(actual.avatarBytes, isNull);
        }
      }
      expect(storage.calls, 0);
      expect(media.calls, 0);
      expect(requests, [
        'POST /rest/v1/rpc/get_or_create_my_profile',
        'GET /rest/v1/profile_photos',
        'POST /rest/v1/rpc/get_or_create_my_profile',
        'GET /rest/v1/profile_photos',
      ]);
    },
  );
}

class _UnusedAvatarStorage implements AvatarStorageDataSource {
  var calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError(
      'Removed photo must not be imported/downloaded: $invocation',
    );
  }
}

class _UnusedMediaCache implements MediaCacheService {
  var calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Removed photo must not use stale media: $invocation');
  }
}
