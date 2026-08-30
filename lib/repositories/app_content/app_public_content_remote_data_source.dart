import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class AppPublicContentRemoteDataSource {
  const AppPublicContentRemoteDataSource({required this._client});

  final SupabaseClient _client;

  Future<AppPublicContent?> fetch() async {
    final response = await _client.rpc<List<dynamic>>('get_public_app_content');
    if (response.isEmpty) return null;
    final row = Map<String, dynamic>.from(response.first as Map);
    return AppPublicContent(
      supportEmail: _string(row['support_email']),
      termsUrlRu: _string(row['terms_url_ru']),
      termsUrlEn: _string(row['terms_url_en']),
      privacyPolicyUrlRu: _string(row['privacy_policy_url_ru']),
      privacyPolicyUrlEn: _string(row['privacy_policy_url_en']),
      telegramUrl: _string(row['telegram_url']),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '')?.toUtc(),
    );
  }

  String? _string(Object? value) {
    final text = value as String?;
    return text == null || text.trim().isEmpty ? null : text.trim();
  }
}
