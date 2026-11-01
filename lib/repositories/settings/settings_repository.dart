import 'dart:async';
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
  int _privacyWriteGeneration = 0;
  final _privacyEvents =
      StreamController<
        ({AccountSessionSnapshot scope, bool visible})
      >.broadcast();

  @override
  Future<AppLanguage?> readCachedAppLanguage() async {
    final scope = _accountSessionController.capture();
    try {
      final cached = await _cache.readAppLanguage(scope.userId);
      _accountSessionController.ensureCurrent(scope);
      return cached;
    } catch (_) {
      _accountSessionController.ensureCurrent(scope);
      return null;
    }
  }

  @override
  Future<AppLanguage?> refreshAppLanguage() async {
    final scope = _accountSessionController.capture();
    final language = await _remote.fetchAppLanguage();
    if (language != null) {
      try {
        await _accountSessionController.commit(
          scope,
          () => _cache.writeAppLanguage(scope.userId, language),
        );
      } catch (error) {
        if (error is StaleAccountSessionException) rethrow;
      }
    }
    _accountSessionController.ensureCurrent(scope);
    return language;
  }

  @override
  Future<AppLanguage> updateAppLanguage(AppLanguage language) async {
    final scope = _accountSessionController.capture();
    final updated = await _remote.updateAppLanguage(language);
    try {
      await _accountSessionController.commit(
        scope,
        () => _cache.writeAppLanguage(scope.userId, updated),
      );
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
    }
    _accountSessionController.ensureCurrent(scope);
    return updated;
  }

  @override
  Stream<bool> watchNearbyVisibility() {
    final scope = _accountSessionController.capture();
    return Stream<bool>.multi((controller) {
      var receivedConfirmation = false;
      var cancelled = false;
      final confirmed = _privacyEvents.stream.listen((event) {
        if (_accountSessionController.isCurrent(scope) &&
            event.scope.userId == scope.userId &&
            event.scope.generation == scope.generation) {
          receivedConfirmation = true;
          controller.add(event.visible);
        }
      });
      // Subscribe before reading disk so a fast confirmed write cannot be
      // replaced by the older initial cache read (including a disk failure).
      unawaited(
        _cache
            .read(scope.userId)
            .then(
              (settings) {
                if (!cancelled &&
                    !receivedConfirmation &&
                    _accountSessionController.isCurrent(scope)) {
                  controller.add(settings?.nearbyVisible ?? true);
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!cancelled &&
                    !receivedConfirmation &&
                    _accountSessionController.isCurrent(scope)) {
                  controller.addError(error, stack);
                }
              },
            ),
      );
      controller.onCancel = () async {
        cancelled = true;
        await confirmed.cancel();
      };
    }).distinct();
  }

  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async {
    final scope = _accountSessionController.capture();
    try {
      final cached = await _cache.read(scope.userId);
      _accountSessionController.ensureCurrent(scope);
      return cached;
    } catch (_) {
      // A damaged local cache must not prevent the following server refresh.
      _accountSessionController.ensureCurrent(scope);
      return null;
    }
  }

  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() async {
    final scope = _accountSessionController.capture();
    final generation = _privacyWriteGeneration;
    final SearchPrivacySettings settings;
    try {
      settings = await _remote.fetchSearchPrivacySettings();
    } catch (_) {
      _accountSessionController.ensureCurrent(scope);
      rethrow;
    }
    if (generation != _privacyWriteGeneration) {
      _accountSessionController.ensureCurrent(scope);
      return await _cache.read(scope.userId) ?? settings;
    }
    try {
      await _accountSessionController.commit(scope, () async {
        if (generation == _privacyWriteGeneration) {
          await _cache.write(scope.userId, settings);
        }
      });
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
      // The server result remains authoritative if only the local cache
      // failed to persist it.
    }
    _accountSessionController.ensureCurrent(scope);
    if (generation == _privacyWriteGeneration) {
      _privacyEvents.add((scope: scope, visible: settings.nearbyVisible));
    }
    return settings;
  }

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async {
    final scope = _accountSessionController.capture();
    _privacyWriteGeneration++;
    final updated = await _remote.updateSearchPrivacySetting(key, value);
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
    _privacyWriteGeneration++;
    _privacyEvents.add((scope: scope, visible: updated.nearbyVisible));
    return updated;
  }

  @override
  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) async {
    final scope = _accountSessionController.capture();
    _privacyWriteGeneration++;
    final updated = await _remote.updateLastSeenVisibility(visibility);
    try {
      await _accountSessionController.commit(
        scope,
        () => _cache.write(scope.userId, updated),
      );
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
    }
    _accountSessionController.ensureCurrent(scope);
    _privacyWriteGeneration++;
    _privacyEvents.add((scope: scope, visible: updated.nearbyVisible));
    return updated;
  }

  @override
  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) async {
    final scope = _accountSessionController.capture();
    _privacyWriteGeneration++;
    final updated = await _remote.updateLocationVisibility(
      sharePreciseLocation: sharePreciseLocation,
      shareDistance: shareDistance,
    );
    await _writeSettings(scope, updated);
    _privacyWriteGeneration++;
    _privacyEvents.add((scope: scope, visible: updated.nearbyVisible));
    return updated;
  }

  @override
  Future<Set<String>> readCachedPreciseLocationExclusions() async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readPreciseLocationExclusions(scope.userId);
    _accountSessionController.ensureCurrent(scope);
    return cached;
  }

  @override
  Future<Set<String>> refreshPreciseLocationExclusions() async {
    final scope = _accountSessionController.capture();
    final exclusions = await _remote.fetchPreciseLocationExclusions();
    await _accountSessionController.commit(
      scope,
      () => _cache.replacePreciseLocationExclusions(scope.userId, exclusions),
    );
    return exclusions;
  }

  @override
  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  }) async {
    final scope = _accountSessionController.capture();
    final exclusions = await _remote.setPreciseLocationExcluded(
      friendUserId,
      excluded: excluded,
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.replacePreciseLocationExclusions(scope.userId, exclusions),
    );
    return exclusions;
  }

  Future<void> _writeSettings(
    AccountSessionSnapshot scope,
    SearchPrivacySettings settings,
  ) async {
    try {
      await _accountSessionController.commit(
        scope,
        () => _cache.write(scope.userId, settings),
      );
    } catch (error) {
      if (error is StaleAccountSessionException) rethrow;
    }
    _accountSessionController.ensureCurrent(scope);
  }

  @override
  Future<void> clearUserCache(String userId) => _cache.clearUser(userId);
}
