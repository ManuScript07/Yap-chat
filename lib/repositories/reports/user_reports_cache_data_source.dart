import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores only server-accepted report timestamps. It is an account-scoped
/// local throttle, never a source of truth for moderation.
class UserReportsCacheDataSource {
  UserReportsCacheDataSource({
    required SharedPreferences preferences,
    required String environment,
  }) : _preferences = preferences,
       _keyPrefix = 'user_reports.accepted.$environment.';

  final SharedPreferences _preferences;
  final String _keyPrefix;

  Future<Map<String, DateTime>> read(String ownerUserId) async {
    final raw = _preferences.getString(_key(ownerUserId));
    if (raw == null) return const {};
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final reports = <String, DateTime>{};
      for (final entry in value.entries) {
        final timestamp = DateTime.tryParse(entry.value as String? ?? '');
        if (timestamp != null) reports[entry.key] = timestamp.toUtc();
      }
      return reports;
    } catch (_) {
      await _preferences.remove(_key(ownerUserId));
      return const {};
    }
  }

  Future<void> record(
    String ownerUserId,
    String targetUserId,
    DateTime createdAt,
  ) async {
    final reports = await read(ownerUserId);
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final retained = <String, DateTime>{
      for (final entry in reports.entries)
        if (entry.value.isAfter(cutoff)) entry.key: entry.value,
      targetUserId: createdAt.toUtc(),
    };
    final persisted = await _preferences.setString(
      _key(ownerUserId),
      jsonEncode({
        for (final entry in retained.entries)
          entry.key: entry.value.toIso8601String(),
      }),
    );
    if (!persisted) throw StateError('Could not cache report throttle.');
  }

  Future<void> clearUser(String ownerUserId) =>
      _preferences.remove(_key(ownerUserId));

  String _key(String ownerUserId) => '$_keyPrefix$ownerUserId';
}
