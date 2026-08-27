import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/profile/data/data.dart';

class ProfileCacheDataSource {
  const ProfileCacheDataSource({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  Future<UserProfile?> read(String userId) async {
    final row = await (_database.select(
      _database.cachedProfiles,
    )..where((table) => table.userId.equals(userId))).getSingleOrNull();
    if (row == null) return null;

    final photoRows = await (_database.select(
      _database.cachedProfilePhotos,
    )..where((table) => table.userId.equals(userId))).get();
    photoRows.sort((left, right) => left.position.compareTo(right.position));
    final photos = photoRows
        .map(
          (photo) => ProfilePhoto(
            position: photo.position,
            avatarUrl: photo.avatarUrl,
            storagePath: photo.storagePath,
            bytes: photo.bytes,
            updatedAt: photo.updatedAt,
          ),
        )
        .toList(growable: false);

    return UserProfile(
      id: row.userId,
      username: row.username,
      displayName: row.displayName,
      birthDate: row.birthDate,
      avatarUrl: row.avatarUrl,
      avatarStoragePath: row.avatarStoragePath,
      avatarBytes: row.avatarBytes,
      avatarUpdatedAt: row.avatarUpdatedAt,
      photos: photos,
      gender: ProfileGender.fromDatabaseValue(row.gender),
      bio: row.bio,
      onboardingCompleted: row.onboardingCompleted,
      termsAcceptedAt: row.termsAcceptedAt,
      privacyAcceptedAt: row.privacyAcceptedAt,
      createdAt: row.createdAt,
    );
  }

  Future<void> write(UserProfile profile) async {
    await _database.transaction(() async {
      await _database
          .into(_database.cachedProfiles)
          .insertOnConflictUpdate(
            CachedProfilesCompanion.insert(
              userId: profile.id,
              username: profile.username,
              displayName: profile.displayName,
              birthDate: Value(profile.birthDate),
              avatarUrl: Value(profile.avatarUrl),
              avatarStoragePath: Value(profile.avatarStoragePath),
              avatarBytes: Value(profile.avatarBytes),
              avatarUpdatedAt: Value(profile.avatarUpdatedAt),
              gender: profile.gender.databaseValue,
              bio: profile.bio,
              onboardingCompleted: profile.onboardingCompleted,
              termsAcceptedAt: Value(profile.termsAcceptedAt),
              privacyAcceptedAt: Value(profile.privacyAcceptedAt),
              createdAt: Value(profile.createdAt),
              cachedAt: DateTime.now().toUtc(),
            ),
          );

      await (_database.delete(
        _database.cachedProfilePhotos,
      )..where((table) => table.userId.equals(profile.id))).go();
      for (final photo in profile.photos) {
        await _database
            .into(_database.cachedProfilePhotos)
            .insert(
              CachedProfilePhotosCompanion.insert(
                userId: profile.id,
                position: photo.position,
                avatarUrl: Value(photo.avatarUrl),
                storagePath: Value(photo.storagePath),
                bytes: Value(photo.bytes),
                updatedAt: Value(photo.updatedAt),
              ),
            );
      }
    });
  }
}
