import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/data/data.dart';

/// Persists only a confirmed restricted-account state so that a confirmed
/// global ban or pending deletion remains restricted offline.
class AuthAccountAccessCacheDataSource {
  AuthAccountAccessCacheDataSource({
    required SharedPreferences preferences,
    required String environment,
  }) : _preferences = preferences,
       _keyPrefix = 'auth.account_access.$environment.';

  final SharedPreferences _preferences;
  final String _keyPrefix;

  Future<AuthAccountAccess?> read(String userId) async {
    final raw = _preferences.getString(_key(userId));
    if (raw == null) return null;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final isBanned = value['isBanned'] == true;
      final isDeletionPending = value['isDeletionPending'] == true;
      final isDeletionExpired = value['isDeletionExpired'] == true;
      if (!isBanned && !isDeletionPending && !isDeletionExpired) return null;
      final username = (value['username'] as String?)?.trim();
      final supportEmail = (value['supportEmail'] as String?)?.trim();
      final scheduledFor = DateTime.tryParse(
        value['deletionScheduledFor'] as String? ?? '',
      )?.toUtc();
      return AuthAccountAccess(
        isBanned: isBanned,
        isDeletionPending: isDeletionPending,
        isDeletionExpired: isDeletionExpired,
        deletionScheduledFor: scheduledFor,
        username: username == null || username.isEmpty ? null : username,
        supportEmail: supportEmail == null || supportEmail.isEmpty
            ? null
            : supportEmail,
      );
    } catch (_) {
      await _preferences.remove(_key(userId));
      return null;
    }
  }

  Future<void> write(String userId, AuthAccountAccess access) {
    if (!access.isBanned &&
        !access.isDeletionPending &&
        !access.isDeletionExpired) {
      return clear(userId);
    }
    return _preferences.setString(
      _key(userId),
      jsonEncode({
        'isBanned': access.isBanned,
        'isDeletionPending': access.isDeletionPending,
        'isDeletionExpired': access.isDeletionExpired,
        'deletionScheduledFor': access.deletionScheduledFor
            ?.toUtc()
            .toIso8601String(),
        'username': access.username,
        'supportEmail': access.supportEmail,
      }),
    );
  }

  Future<void> clear(String userId) => _preferences.remove(_key(userId));

  String _key(String userId) => '$_keyPrefix$userId';
}
