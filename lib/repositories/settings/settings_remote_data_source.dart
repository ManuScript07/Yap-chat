import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class SettingsRemoteDataSource {
  const SettingsRemoteDataSource({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<AppLanguage?> fetchAppLanguage() async {
    final response = await _client.rpc<List<dynamic>>('get_my_app_language');
    if (response.isEmpty) return null;
    return AppLanguage.tryParse((response.first as Map)['language_code']);
  }

  Future<AppLanguage> updateAppLanguage(AppLanguage language) async {
    final response = await _client.rpc<List<dynamic>>(
      'set_my_app_language',
      params: {'language_code': language.code},
    );
    if (response.isEmpty) {
      throw StateError('Supabase returned no updated app language');
    }
    final updated = AppLanguage.tryParse(
      (response.first as Map)['language_code'],
    );
    if (updated == null) {
      throw StateError('Supabase returned an invalid app language');
    }
    return updated;
  }

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
      sharePreciseLocation: row['share_precise_location'] as bool? ?? true,
      shareDistance: row['share_distance'] as bool? ?? true,
    );
  }

  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) async {
    final response = await _client.rpc<List<dynamic>>(
      'set_my_location_visibility',
      params: {
        'is_precise_location_shared': sharePreciseLocation,
        'is_distance_shared': shareDistance,
      },
    );
    if (response.isEmpty) {
      throw StateError('Supabase returned no privacy settings');
    }
    return _map(response.first);
  }

  Future<Set<String>> fetchPreciseLocationExclusions() async {
    final response = await _client.rpc<List<dynamic>>(
      'get_my_precise_location_exclusions',
    );
    return response
        .map((row) => (row as Map)['viewer_user_id'] as String)
        .toSet();
  }

  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  }) async {
    final response = await _client.rpc<List<dynamic>>(
      'set_precise_location_excluded',
      params: {'friend_user_id': friendUserId, 'is_excluded': excluded},
    );
    return response
        .map((row) => (row as Map)['viewer_user_id'] as String)
        .toSet();
  }
}
