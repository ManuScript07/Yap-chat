import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/reports/data/data.dart';

class UserReportsRemoteDataSource {
  const UserReportsRemoteDataSource({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<DateTime> submit({
    required String targetUserId,
    required UserReportReason reason,
  }) async {
    final value = await _client.rpc<dynamic>(
      'submit_user_report',
      params: {
        'target_user_id': targetUserId,
        'report_reason': reason.databaseValue,
      },
    );
    final createdAt = DateTime.tryParse(value as String? ?? '');
    if (createdAt == null) throw StateError('Invalid report submission result.');
    return createdAt.toUtc();
  }
}
