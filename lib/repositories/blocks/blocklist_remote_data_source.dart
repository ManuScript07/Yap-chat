import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';

class BlocklistRemoteDataSource {
  const BlocklistRemoteDataSource({
    required SupabaseClient client,
    AppDiagnostics? diagnostics,
  }) : _client = client,
       _diagnostics = diagnostics;

  final SupabaseClient _client;
  final AppDiagnostics? _diagnostics;

  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final response = await measureRpc(
      _diagnostics,
      'get_blocked_users',
      () => _client.rpc<List<dynamic>>('get_blocked_users'),
    );
    return response
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final storagePath = row['avatar_storage_path'] as String?;
          return BlockedUser(
            id: row['id'] as String,
            username: row['username'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
            avatarUrl: storagePath == null
                ? row['avatar_url'] as String?
                : null,
            avatarStoragePath: storagePath,
            blockedAt: DateTime.parse(row['created_at'] as String).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<void> blockUser(String userId) => measureRpc(
    _diagnostics,
    'block_user',
    () => _client.rpc<void>('block_user', params: {'target_user_id': userId}),
  );

  Future<void> unblockUser(String userId) => measureRpc(
    _diagnostics,
    'unblock_user',
    () => _client.rpc<void>('unblock_user', params: {'target_user_id': userId}),
  );
}
