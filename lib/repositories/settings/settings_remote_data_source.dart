import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class SettingsRemoteDataSource {
  const SettingsRemoteDataSource({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<SearchPrivacySettings> fetchSearchPrivacySettings() async {
    final response = await _client.rpc<List<dynamic>>(
      'get_my_search_privacy_settings',
    );
    if (response.isEmpty) return const SearchPrivacySettings();
    return _map(response.first);
  }

  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async {
    final response = await _client.rpc<List<dynamic>>(
      'set_my_search_privacy_setting',
      params: {'setting_key': key.name, 'is_enabled': value},
    );
    if (response.isEmpty) {
      throw StateError('Supabase returned no updated search privacy settings');
    }
    return _map(response.first);
  }

  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) async {
    final response = await _client.rpc<List<dynamic>>(
      'set_my_last_seen_visibility',
      params: {'visibility': visibility.name},
    );
    if (response.isEmpty) {
      throw StateError('Supabase returned no updated privacy settings');
    }
    return _map(response.first);
  }

  SearchPrivacySettings _map(dynamic value) {
    final row = Map<String, dynamic>.from(value as Map);
    return SearchPrivacySettings(
      searchByUsername: row['search_by_username'] as bool? ?? true,
      searchByPhone: row['search_by_phone'] as bool? ?? true,
      searchByName: row['search_by_name'] as bool? ?? true,
      lastSeenVisibility:
          LastSeenVisibility.values
              .where((item) => item.name == row['last_seen_visibility'])
              .firstOrNull ??
          LastSeenVisibility.all,
    );
  }
}
