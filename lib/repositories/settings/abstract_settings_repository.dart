import 'package:yap_chat/features/settings/data/data.dart';

abstract interface class ISettingsRepository {
  /// Returns the account-scoped language without contacting the server.
  Future<AppLanguage?> readCachedAppLanguage();

  /// Gets the saved account language, if it was selected by the user.
  Future<AppLanguage?> refreshAppLanguage();

  /// Persists the selected language and refreshes its local account cache.
  Future<AppLanguage> updateAppLanguage(AppLanguage language);

  /// Returns the last account-scoped value, if any, without network access.
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings();

  /// Gets the authoritative value and refreshes the local cache.
  Future<SearchPrivacySettings> refreshSearchPrivacySettings();

  /// Updates exactly one setting, avoiding cross-device stale overwrites.
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  );

  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  );

  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  });

  Future<Set<String>> readCachedPreciseLocationExclusions();
  Future<Set<String>> refreshPreciseLocationExclusions();
  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  });

  Future<void> clearUserCache(String userId);
}
