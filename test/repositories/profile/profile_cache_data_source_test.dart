import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';

void main() {
  test('stores and restores a profile with private avatar bytes', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ProfileCacheDataSource(database: database);
    final avatarBytes = Uint8List.fromList([1, 2, 3, 4]);
    final profile = UserProfile(
      id: 'user-id',
      username: 'u0000001',
      displayName: 'Пользователь',
      birthDate: DateTime(2000, 1, 1),
      avatarStoragePath: 'user-id/avatar.jpg',
      avatarBytes: avatarBytes,
      avatarUpdatedAt: DateTime.utc(2026, 8, 19),
      yandexAvatarDisabled: true,
      photos: [
        ProfilePhoto(
          position: 0,
          storagePath: 'user-id/avatar.jpg',
          bytes: avatarBytes,
          updatedAt: DateTime.utc(2026, 8, 19),
        ),
      ],
      onboardingCompleted: true,
      termsAcceptedAt: DateTime.utc(2026, 8, 18),
      privacyAcceptedAt: DateTime.utc(2026, 8, 18),
      createdAt: DateTime.utc(2026, 8, 16),
    );

    await cache.write(profile);
    final rawProfile = await database
        .select(database.cachedProfiles)
        .getSingle();
    final restored = await cache.read(profile.id);

    expect(rawProfile.avatarBytes, isNull);
    expect(restored?.username, profile.username);
    expect(restored?.avatarStoragePath, profile.avatarStoragePath);
    expect(restored?.yandexAvatarDisabled, isTrue);
    expect(restored?.avatarBytes, orderedEquals(avatarBytes));
    expect(restored?.photos, hasLength(1));
    expect(restored?.photos.first.bytes, orderedEquals(avatarBytes));
    expect(
      restored?.createdAt?.isAtSameMomentAs(DateTime.utc(2026, 8, 16)),
      isTrue,
    );
    expect(
      restored?.avatarUpdatedAt?.isAtSameMomentAs(profile.avatarUpdatedAt!),
      isTrue,
    );
  });

  test('persists list order instead of stale embedded positions', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = ProfileCacheDataSource(database: database);
    final acceptedAt = DateTime.utc(2026);
    final profile = UserProfile(
      id: 'user-id',
      username: 'user_name',
      displayName: 'User',
      birthDate: DateTime(2000),
      avatarStoragePath: 'user-id/second.jpg',
      onboardingCompleted: true,
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
      photos: const [
        ProfilePhoto(position: 1, storagePath: 'user-id/second.jpg'),
        ProfilePhoto(position: 0, storagePath: 'user-id/first.jpg'),
      ],
    );

    await cache.write(profile);
    final restored = await cache.read(profile.id);

    expect(restored?.effectivePhotos.map((photo) => photo.storagePath), [
      'user-id/second.jpg',
      'user-id/first.jpg',
    ]);
    expect(restored?.effectivePhotos.map((photo) => photo.position), [0, 1]);
  });

  test(
    'repairs a cached order that disagrees with the primary photo',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = ProfileCacheDataSource(database: database);
      final cachedAt = DateTime.utc(2026);
      await database
          .into(database.cachedProfiles)
          .insert(
            CachedProfilesCompanion.insert(
              userId: 'user-id',
              username: 'user_name',
              displayName: 'User',
              avatarStoragePath: const Value('user-id/second.jpg'),
              gender: ProfileGender.unspecified.databaseValue,
              bio: '',
              onboardingCompleted: true,
              cachedAt: cachedAt,
            ),
          );
      await database
          .into(database.cachedProfilePhotos)
          .insert(
            CachedProfilePhotosCompanion.insert(
              userId: 'user-id',
              position: 0,
              storagePath: Value('user-id/first.jpg'),
            ),
          );
      await database
          .into(database.cachedProfilePhotos)
          .insert(
            CachedProfilePhotosCompanion.insert(
              userId: 'user-id',
              position: 1,
              storagePath: Value('user-id/second.jpg'),
            ),
          );

      final restored = await cache.read('user-id');

      expect(restored?.effectivePhotos.map((photo) => photo.storagePath), [
        'user-id/second.jpg',
        'user-id/first.jpg',
      ]);
      expect(restored?.effectivePhotos.map((photo) => photo.position), [0, 1]);
    },
  );

  test('schema 10 migration removes legacy duplicated avatar blobs', () async {
    final temporary = await Directory.systemTemp.createTemp('yap-db-migration');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/cache.sqlite');
    var database = AppDatabase.forTesting(NativeDatabase(file));
    await database.customStatement('SELECT 1');
    await database.close();

    final raw = sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 9');
    raw.execute('''
      INSERT INTO cached_profiles (
        user_id, username, display_name, avatar_bytes, gender, bio,
        onboarding_completed, cached_at
      ) VALUES ('user', 'username', 'User', X'010203', 'unspecified', '', 1, 0)
    ''');
    raw.close();

    database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);
    final row = await database.select(database.cachedProfiles).getSingle();
    expect(row.avatarBytes, isNull);
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), database.schemaVersion);
  });
}
