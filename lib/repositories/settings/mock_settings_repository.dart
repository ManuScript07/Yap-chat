import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

class MockSettingsRepository implements ISettingsRepository {
  SearchPrivacySettings _settings = const SearchPrivacySettings();

  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async =>
      _settings;

  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() async =>
      _settings;

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async {
    _settings = _settings.withValue(key, value);
    return _settings;
  }

  @override
  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) async {
    _settings = _settings.copyWith(lastSeenVisibility: visibility);
    return _settings;
  }

  @override
  Future<void> clearUserCache(String userId) async {}
}
