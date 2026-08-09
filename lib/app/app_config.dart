import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';

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
  });

  final AppEnvironment environment;
  final SharedPreferences preferences;
  final Talker talker;
  final Map<String, String> env;

  bool get isDev => environment == AppEnvironment.dev;

  String? get backendBaseUrl => env['BACKEND_BASE_URL'];
}
