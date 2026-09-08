import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/abstract_app_public_content_repository.dart';

class AppPublicContentCacheDataSource {
  AppPublicContentCacheDataSource({
    required this._preferences,
    required String environment,
  }) : _key = 'app_public_content.$environment';

  final SharedPreferences _preferences;
  final String _key;

  Future<CachedAppPublicContent?> read() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      // The first deployed version stored the manifest itself. Keep it
      // readable offline, but refresh it immediately because it has no local
      // download timestamp.
      final contentJson = decoded['content'] is Map
          ? Map<String, dynamic>.from(decoded['content'] as Map)
          : decoded;
      return CachedAppPublicContent(
        content: AppPublicContent.fromJson(contentJson),
        fetchedAt: DateTime.tryParse(decoded['fetchedAt'] as String? ?? '')
            ?.toUtc(),
      );
    } catch (_) {
      await _preferences.remove(_key);
      return null;
    }
  }

  Future<void> write(AppPublicContent content, {required DateTime fetchedAt}) =>
      _preferences.setString(
        _key,
        jsonEncode({
          'content': content.toJson(),
          'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        }),
      );
}
