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

    return UserProfile(
      id: row.userId,
      username: row.username,
      displayName: row.displayName,
      birthDate: row.birthDate,
      avatarUrl: row.avatarUrl,
      avatarStoragePath: row.avatarStoragePath,
      avatarBytes: row.avatarBytes,
      avatarUpdatedAt: row.avatarUpdatedAt,
      gender: ProfileGender.fromDatabaseValue(row.gender),
      bio: row.bio,
      onboardingCompleted: row.onboardingCompleted,
      termsAcceptedAt: row.termsAcceptedAt,
      privacyAcceptedAt: row.privacyAcceptedAt,
    );
  }

  Future<void> write(UserProfile profile) async {
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
            cachedAt: DateTime.now().toUtc(),
          ),
        );
  }
}
