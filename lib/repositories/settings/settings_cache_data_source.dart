import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class SettingsCacheDataSource {
  const SettingsCacheDataSource({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  Future<SearchPrivacySettings?> read(String ownerUserId) async {
    final row =
        await (_database.select(_database.cachedSearchPrivacySettings)
              ..where((table) => table.ownerUserId.equals(ownerUserId)))
            .getSingleOrNull();
    if (row == null) return null;
    return SearchPrivacySettings(
      searchByUsername: row.searchByUsername,
      searchByPhone: row.searchByPhone,
      searchByName: row.searchByName,
      lastSeenVisibility: _lastSeenVisibility(row.lastSeenVisibility),
    );
  }

  Future<void> write(String ownerUserId, SearchPrivacySettings settings) async {
    await _database
        .into(_database.cachedSearchPrivacySettings)
        .insertOnConflictUpdate(
          CachedSearchPrivacySettingsCompanion.insert(
            ownerUserId: ownerUserId,
            searchByUsername: settings.searchByUsername,
            searchByPhone: settings.searchByPhone,
            searchByName: settings.searchByName,
            lastSeenVisibility: Value(settings.lastSeenVisibility.name),
            cachedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> clearUser(String ownerUserId) async {
    await (_database.delete(
      _database.cachedSearchPrivacySettings,
    )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
  }

  LastSeenVisibility _lastSeenVisibility(String value) =>
      LastSeenVisibility.values
          .where((item) => item.name == value)
          .firstOrNull ??
      LastSeenVisibility.all;
}
