import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/settings/data/data.dart';

class AppPublicContentRemoteDataSource {
  const AppPublicContentRemoteDataSource({
    required this.client,
    this.bucket = _defaultBucket,
    this.path = _defaultPath,
    this.timeout = _defaultTimeout,
  });

  static const _defaultBucket = 'legal-documents';
  static const _defaultPath = 'app-content.json';
  static const _defaultTimeout = Duration(seconds: 5);

  final SupabaseClient client;
  final String bucket;
  final String path;
  final Duration timeout;

  Future<AppPublicContent?> fetch() async {
    final bytes = await client.storage
        .from(bucket)
        .download(path)
        .timeout(timeout);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    return AppPublicContent.fromJson(Map<String, dynamic>.from(decoded));
  }
}
