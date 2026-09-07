import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';

class NearbyPageResult {
  const NearbyPageResult({required this.people, required this.hasMore});

  final List<NearbyPerson> people;
  final bool hasMore;
}

class NearbyRemoteDataSource {
  const NearbyRemoteDataSource({
    required SupabaseClient client,
    PresenceStatusStore? presenceStore,
    AppDiagnostics? diagnostics,
  }) : _client = client,
       _presenceStore = presenceStore,
       _diagnostics = diagnostics;

  final SupabaseClient _client;
  final PresenceStatusStore? _presenceStore;
  final AppDiagnostics? _diagnostics;
  static const _requestTimeout = Duration(seconds: 10);

  Future<NearbyPageResult> fetch({
    required NearbyFilters filters,
    String? afterUserId,
  }) async {
    final response = await measureRpc(
      _diagnostics,
      'get_nearby_people',
      () => _client
          .rpc<List<dynamic>>(
            'get_nearby_people',
            params: {
              'preferred_gender': filters.gender?.databaseValue,
              'minimum_age': filters.minimumAge,
              'maximum_age': filters.maximumAge,
              'after_user_id': afterUserId,
              'page_size': 30,
            },
          )
          .timeout(_requestTimeout),
    );
    final rows = response
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    _presenceStore?.recordAll({
      for (final row in rows)
        if (row['id'] is String && row['is_online'] is bool)
          row['id'] as String: row['is_online'] as bool,
    });
    return NearbyPageResult(
      people: List.unmodifiable(rows.map(NearbyPerson.fromMap)),
      hasMore: rows.isNotEmpty && (rows.first['has_more'] as bool? ?? false),
    );
  }
}
