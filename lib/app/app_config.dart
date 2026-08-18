import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/database/database.dart';

enum AppEnvironment { dev, prod }

/// Низкоуровневые зависимости приложения: SDK, клиенты, логгер и env-настройки.
///
/// В этот класс не попадают репозитории фич — они создаются в
/// [RepositoryContainer], чтобы app-слой не знал деталей конкретных модулей.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.preferences,
    required this.talker,
    required this.env,
    required this.database,
    this.supabaseClient,
  });

  final AppEnvironment environment;
  final SharedPreferences preferences;
  final Talker talker;
  final Map<String, String> env;
  final AppDatabase database;
  final SupabaseClient? supabaseClient;

  bool get isDev => environment == AppEnvironment.dev;

  String? get backendBaseUrl => env['BACKEND_BASE_URL'];

  String get authRedirectUrl =>
      env['AUTH_REDIRECT_URL']?.trim().isNotEmpty == true
      ? env['AUTH_REDIRECT_URL']!.trim()
      : 'yapchat://login-callback/';

  SupabaseClient requireSupabaseClient() {
    final client = supabaseClient;
    if (client == null) {
      throw StateError(
        'Supabase is not configured. Add SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY to .env.',
      );
    }
    return client;
  }
}
