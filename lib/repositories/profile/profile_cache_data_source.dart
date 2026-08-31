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
    var photos = photoRows
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
    photos = _alignPrimaryPhoto(
      photos,
      avatarUrl: row.avatarUrl,
      storagePath: row.avatarStoragePath,
    );

    return UserProfile(
      id: row.userId,
      username: row.username,
      displayName: row.displayName,
      birthDate: row.birthDate,
      avatarUrl: row.avatarUrl,
      avatarStoragePath: row.avatarStoragePath,
      avatarBytes: photos.firstOrNull?.bytes ?? row.avatarBytes,
      avatarUpdatedAt: row.avatarUpdatedAt,
      yandexAvatarDisabled: row.yandexAvatarDisabled,
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
              // The primary photo already exists in cachedProfilePhotos.
              // Keep the legacy column empty while retaining read compatibility.
              avatarBytes: const Value(null),
              avatarUpdatedAt: Value(profile.avatarUpdatedAt),
              yandexAvatarDisabled: Value(profile.yandexAvatarDisabled),
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
      final photos = profile.effectivePhotos;
      for (var index = 0; index < photos.length; index++) {
        final photo = photos[index];
        await _database
            .into(_database.cachedProfilePhotos)
            .insert(
              CachedProfilePhotosCompanion.insert(
                userId: profile.id,
                // The list order is authoritative. A stale embedded position
                // must never make a successful reorder revert after restart.
                position: index,
                avatarUrl: Value(photo.avatarUrl),
                storagePath: Value(photo.storagePath),
                bytes: Value(photo.bytes),
                updatedAt: Value(photo.updatedAt),
              ),
            );
      }
    });
  }

  List<ProfilePhoto> _alignPrimaryPhoto(
    List<ProfilePhoto> photos, {
    required String? avatarUrl,
    required String? storagePath,
  }) {
    if (photos.length < 2) return photos;
    final primaryIndex = photos.indexWhere(
      (photo) => storagePath != null
          ? photo.storagePath == storagePath
          : avatarUrl != null && photo.avatarUrl == avatarUrl,
    );
    if (primaryIndex <= 0) return photos;

    final aligned = photos.toList()..insert(0, photos[primaryIndex]);
    aligned.removeAt(primaryIndex + 1);
    return List<ProfilePhoto>.unmodifiable([
      for (var index = 0; index < aligned.length; index++)
        aligned[index].copyWith(position: index),
    ]);
  }
}
