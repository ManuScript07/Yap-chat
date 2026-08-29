import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/repositories/auth/auth.dart';

enum AppEnvironment { dev, local, prod }

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
    this.oauthAttemptCoordinator,
    this.supabaseClient,
    this.firebaseMessaging,
  });

  final AppEnvironment environment;
  final SharedPreferences preferences;
  final Talker talker;
  final Map<String, String> env;
  final AppDatabase database;
  final OAuthAttemptCoordinator? oauthAttemptCoordinator;
  final SupabaseClient? supabaseClient;
  final FirebaseMessaging? firebaseMessaging;

  bool get isDev => environment == AppEnvironment.dev;

  bool get isLocal => environment == AppEnvironment.local;

  String? get backendBaseUrl => env['BACKEND_BASE_URL'];

  String get authRedirectUrl => resolveAuthRedirectUrl(env);

  static String resolveAuthRedirectUrl(Map<String, String> env) =>
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
