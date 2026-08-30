import 'package:yap_chat/features/settings/data/data.dart';

abstract interface class ISettingsRepository {
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

  Future<void> clearUserCache(String userId);
}
