import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';
import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/reports/abstract_user_reports_repository.dart';
import 'package:yap_chat/repositories/nearby/abstract_nearby_repository.dart';

/// Durable, account-scoped cleanup used by logout and startup recovery.
class UserDataCleanupCoordinator {
  UserDataCleanupCoordinator({
    required SharedPreferences preferences,
    required String environment,
    required AccountSessionController accountSessionController,
    required ILocalMediaRepository localMediaRepository,
    required MediaCacheService mediaCache,
    ISettingsRepository? settingsRepository,
    IBlocklistRepository? blocklistRepository,
    IUserReportsRepository? userReportsRepository,
    INearbyRepository? nearbyRepository,
    required Talker talker,
  }) : _preferences = preferences,
       _pendingKey = 'auth.cleanup.pending.$environment',
       _accountSessionController = accountSessionController,
       _localMediaRepository = localMediaRepository,
       _mediaCache = mediaCache,
       _settingsRepository = settingsRepository,
       _blocklistRepository = blocklistRepository,
       _userReportsRepository = userReportsRepository,
       _nearbyRepository = nearbyRepository,
       _talker = talker;

  final SharedPreferences _preferences;
  final String _pendingKey;
  final AccountSessionController _accountSessionController;
  final ILocalMediaRepository _localMediaRepository;
  final MediaCacheService _mediaCache;
  final ISettingsRepository? _settingsRepository;
  final IBlocklistRepository? _blocklistRepository;
  final IUserReportsRepository? _userReportsRepository;
  final INearbyRepository? _nearbyRepository;
  final Talker _talker;

  Future<void> _operation = Future<void>.value();

  Future<void> markPending(String userId) => _enqueue(() async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    final pending = _pendingUsers()..add(normalized);
    final persisted = await _preferences.setStringList(
      _pendingKey,
      pending.toList()..sort(),
    );
    if (!persisted) throw StateError('Could not persist logout cleanup marker');
  });

  Future<void> clearUser(String userId) =>
      _enqueue(() => _clearUser(userId.trim()));

  Future<void> resumePendingCleanup() => _enqueue(() async {
    for (final userId in _pendingUsers().toList(growable: false)) {
      await _clearUser(userId);
    }
  });

  bool isPending(String userId) => _pendingUsers().contains(userId.trim());

  Future<void> _clearUser(String userId) async {
    if (userId.isEmpty) return;
    try {
      await _accountSessionController.drainCommits();
      await Future.wait([
        _localMediaRepository.clearUser(userId),
        _mediaCache.clearUser(userId),
        if (_settingsRepository case final repository?)
          repository.clearUserCache(userId),
        if (_blocklistRepository case final repository?)
          repository.clearUserCache(userId),
        if (_userReportsRepository case final repository?)
          repository.clearUserCache(userId),
        if (_nearbyRepository case final repository?)
          repository.clearUserCache(userId),
        _clearPreferences(userId),
      ]);
      final pending = _pendingUsers()..remove(userId);
      if (pending.isEmpty) {
        await _preferences.remove(_pendingKey);
      } else {
        await _preferences.setStringList(_pendingKey, pending.toList()..sort());
      }
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Account local data cleanup failed');
    }
  }

  Future<void> _clearPreferences(String userId) async {
    final keys = _preferences.getKeys().where(
      (key) =>
          key.startsWith('tracked_location.$userId.') ||
          key.startsWith('permission_reminder.$userId.'),
    );
    await Future.wait(keys.map(_preferences.remove));
  }

  Set<String> _pendingUsers() =>
      (_preferences.getStringList(_pendingKey) ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operation.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _operation = result.catchError((_) {});
    return result;
  }
}
