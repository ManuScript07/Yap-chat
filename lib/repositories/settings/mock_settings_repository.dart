import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

class MockSettingsRepository implements ISettingsRepository {
  SearchPrivacySettings _settings = const SearchPrivacySettings();
  final Set<String> _preciseLocationExclusions = {};

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
  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) async {
    _settings = _settings.copyWith(
      sharePreciseLocation: sharePreciseLocation,
      shareDistance: shareDistance,
    );
    return _settings;
  }

  @override
  Future<Set<String>> readCachedPreciseLocationExclusions() async =>
      Set.unmodifiable(_preciseLocationExclusions);

  @override
  Future<Set<String>> refreshPreciseLocationExclusions() async =>
      Set.unmodifiable(_preciseLocationExclusions);

  @override
  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  }) async {
    if (excluded) {
      _preciseLocationExclusions.add(friendUserId);
    } else {
      _preciseLocationExclusions.remove(friendUserId);
    }
    return Set.unmodifiable(_preciseLocationExclusions);
  }

  @override
  Future<void> clearUserCache(String userId) async {}
}
