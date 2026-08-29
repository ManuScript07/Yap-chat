import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';
import 'package:yap_chat/repositories/settings/settings_cache_data_source.dart';
import 'package:yap_chat/repositories/settings/settings_remote_data_source.dart';

class SettingsRepository implements ISettingsRepository {
  SettingsRepository({
    required SettingsCacheDataSource cache,
    required SettingsRemoteDataSource remote,
    required AccountSessionController accountSessionController,
  }) : _cache = cache,
       _remote = remote,
       _accountSessionController = accountSessionController;

  final SettingsCacheDataSource _cache;
  final SettingsRemoteDataSource _remote;
  final AccountSessionController _accountSessionController;

  @override
  Future<SearchPrivacySettings> getSearchPrivacySettings() async {
    final scope = _accountSessionController.capture();
    SearchPrivacySettings? cached;
    try {
      cached = await _cache.read(scope.userId);
    } catch (_) {
      // A damaged local cache must not prevent an authoritative server read.
    }
    final SearchPrivacySettings settings;
    try {
      settings = await _remote.fetchSearchPrivacySettings();
    } catch (_) {
      _accountSessionController.ensureCurrent(scope);
      if (cached != null) return cached;
      rethrow;
    }
    try {
      await _accountSessionController.commit(
        scope,
        () => _cache.write(scope.userId, settings),
      );
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
      // The server result remains authoritative if only the local cache
      // failed to persist it.
    }
    _accountSessionController.ensureCurrent(scope);
    return settings;
  }

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySettings(
    SearchPrivacySettings settings,
  ) async {
    final scope = _accountSessionController.capture();
    final updated = await _remote.updateSearchPrivacySettings(settings);
    try {
      await _accountSessionController.commit(
        scope,
        () => _cache.write(scope.userId, updated),
      );
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
      // A successful server update must not be reported as failed merely
      // because the optional local cache could not be written.
    }
    _accountSessionController.ensureCurrent(scope);
    return updated;
  }

  @override
  Future<void> clearUserCache(String userId) => _cache.clearUser(userId);
}
