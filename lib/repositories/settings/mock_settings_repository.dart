import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

class MockSettingsRepository implements ISettingsRepository {
  SearchPrivacySettings _settings = const SearchPrivacySettings();

  @override
  Future<SearchPrivacySettings> getSearchPrivacySettings() async => _settings;

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySettings(
    SearchPrivacySettings settings,
  ) async {
    _settings = settings;
    return _settings;
  }

  @override
  Future<void> clearUserCache(String userId) async {}
}
