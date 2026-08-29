import 'package:yap_chat/features/settings/data/data.dart';

abstract interface class ISettingsRepository {
  Future<SearchPrivacySettings> getSearchPrivacySettings();

  Future<SearchPrivacySettings> updateSearchPrivacySettings(
    SearchPrivacySettings settings,
  );

  Future<void> clearUserCache(String userId);
}
