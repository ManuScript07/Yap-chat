import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class AppPublicContentCacheDataSource {
  AppPublicContentCacheDataSource({
    required this._preferences,
    required String environment,
  }) : _key = 'app_public_content.$environment';

  final SharedPreferences _preferences;
  final String _key;

  Future<AppPublicContent?> read() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      return AppPublicContent.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      await _preferences.remove(_key);
      return null;
    }
  }

  Future<void> write(AppPublicContent content) =>
      _preferences.setString(_key, jsonEncode(content.toJson()));
}
