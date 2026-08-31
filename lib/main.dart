import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/chat/local_media_repository.dart';
import 'package:yap_chat/repositories/auth/auth.dart';
import 'package:yap_chat/repositories/notifications/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(isOptional: true);
  await initializeDateFormatting();

  final talker = Talker();
  final preferences = await SharedPreferences.getInstance();
  final environment = _resolveEnvironment(dotenv.env);
  final authRedirectUrl = AppConfig.resolveAuthRedirectUrl(dotenv.env);
  final oauthAttemptCoordinator = OAuthAttemptCoordinator(
    preferences: preferences,
    namespace: environment.name,
  );
  final database = AppDatabase(name: _databaseName(environment));
  final supabaseClient = await _initializeSupabase(
    dotenv.env,
    authRedirectUrl: authRedirectUrl,
    oauthAttemptCoordinator: oauthAttemptCoordinator,
    preferences: preferences,
    storageNamespace: environment.name,
  );
  final accountSessionController = AccountSessionController(
    initialUserId:
        environment == AppEnvironment.dev &&
            (preferences.getBool(MockAuthRepository.signedInPreferenceKey) ??
                false)
        ? MockAuthRepository.mockUserId
        : supabaseClient?.auth.currentUser?.id,
  );
  final firebaseMessaging = environment == AppEnvironment.prod
      ? await _initializeFirebase(talker)
      : null;
  if (firebaseMessaging == null) {
    await preferences.remove(
      PushNotificationsRepository.currentUserPreferenceKey,
    );
  }

  String? currentOwnerUserId() {
    if (environment == AppEnvironment.dev) {
      final isSignedIn =
          preferences.getBool(MockAuthRepository.signedInPreferenceKey) ??
          false;
      return isSignedIn ? MockAuthRepository.mockUserId : null;
    }
    return supabaseClient?.auth.currentUser?.id;
  }

  final localMediaRepository = LocalMediaRepository(
    preferences: preferences,
    database: database,
    accountSessionController: accountSessionController,
    ownerUserIdProvider: currentOwnerUserId,
    environment: environment.name,
  );
  final lostPhotoPath = await MediaService.retrieveLostPhoto();
  if (lostPhotoPath != null) {
    final persistedPath = await localMediaRepository.persistMedia(
      lostPhotoPath,
    );
    if (persistedPath != null) {
      await localMediaRepository.savePendingMedia(persistedPath);
    }
  }

  Bloc.observer = TalkerBlocObserver(
    talker: talker,
    settings: const TalkerBlocLoggerSettings(
      // Full Equatable payloads may contain image bytes and personal data.
      // Keeping only runtime types preserves the event timeline without
      // serializing megabytes of data on the UI isolate.
      printEventFullData: false,
      printStateFullData: false,
    ),
  );

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  final config = AppConfig(
    environment: environment,
    preferences: preferences,
    talker: talker,
    env: Map.unmodifiable(dotenv.env),
    database: database,
    accountSessionController: accountSessionController,
    oauthAttemptCoordinator: oauthAttemptCoordinator,
    supabaseClient: supabaseClient,
    firebaseMessaging: firebaseMessaging,
  );

  runApp(App(config: config));
}

Future<FirebaseMessaging?> _initializeFirebase(Talker talker) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(handlePushNotificationInBackground);
    return FirebaseMessaging.instance;
  } catch (error, stackTrace) {
    talker.handle(
      error,
      stackTrace,
      'Firebase is not configured; push notifications are disabled',
    );
    return null;
  }
}

Future<SupabaseClient?> _initializeSupabase(
  Map<String, String> env, {
  required String authRedirectUrl,
  required OAuthAttemptCoordinator oauthAttemptCoordinator,
  required SharedPreferences preferences,
  required String storageNamespace,
}) async {
  final url = env['SUPABASE_URL']?.trim();
  final publishableKey = env['SUPABASE_PUBLISHABLE_KEY']?.trim();
  if (url == null ||
      url.isEmpty ||
      publishableKey == null ||
      publishableKey.isEmpty) {
    return null;
  }

  // A verifier from the previous SharedPreferences implementation cannot be
  // safely resumed after this upgrade. Remove it before GoTrue can observe it.
  await preferences.remove(
    SecureSupabasePkceStorage.legacySharedPreferencesKey,
  );

  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SecureSupabaseSessionStorage(
        key: _supabaseSessionStorageKey(url),
        legacyPreferences: preferences,
      ),
      pkceAsyncStorage: SecureSupabasePkceStorage(namespace: storageNamespace),
      detectSessionInUriPredicate: kIsWeb
          ? null
          : (uri) =>
                isConfiguredAuthCallback(uri, authRedirectUrl) &&
                oauthAttemptCoordinator.tryAcceptCallback(uri),
    ),
  );
  return Supabase.instance.client;
}

String _supabaseSessionStorageKey(String url) =>
    'sb-${Uri.parse(url).host.split('.').first}-auth-token';

AppEnvironment _resolveEnvironment(Map<String, String> env) {
  final rawEnvironment = env['APP_ENV']?.trim().toLowerCase();
  return switch (rawEnvironment) {
    'prod' || 'production' => AppEnvironment.prod,
    'local' => AppEnvironment.local,
    _ => AppEnvironment.dev,
  };
}

String _databaseName(AppEnvironment environment) => switch (environment) {
  AppEnvironment.prod => 'yap_chat_cache',
  AppEnvironment.local => 'yap_chat_cache_local',
  AppEnvironment.dev => 'yap_chat_cache_dev',
};
