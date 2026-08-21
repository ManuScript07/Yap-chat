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
import 'package:yap_chat/core/services/media_service.dart';
import 'package:yap_chat/repositories/chat/local_media_repository.dart';
import 'package:yap_chat/repositories/notifications/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(isOptional: true);
  await initializeDateFormatting();

  final talker = Talker();
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase();
  final environment = _resolveEnvironment(dotenv.env);
  final supabaseClient = await _initializeSupabase(dotenv.env);
  final firebaseMessaging = environment == AppEnvironment.prod
      ? await _initializeFirebase(talker)
      : null;
  if (firebaseMessaging == null) {
    await preferences.remove(
      PushNotificationsRepository.currentUserPreferenceKey,
    );
  }

  final localMediaRepository = LocalMediaRepository(preferences: preferences);
  final lostPhotoPath = await MediaService.retrieveLostPhoto();
  if (lostPhotoPath != null) {
    final persistedPath = await localMediaRepository.persistMedia(
      lostPhotoPath,
    );
    if (persistedPath != null) {
      await localMediaRepository.savePendingMedia(persistedPath);
    }
  }

  Bloc.observer = TalkerBlocObserver(talker: talker);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final config = AppConfig(
    environment: environment,
    preferences: preferences,
    talker: talker,
    env: Map.unmodifiable(dotenv.env),
    database: database,
    supabaseClient: supabaseClient,
    firebaseMessaging: firebaseMessaging,
  );

  runApp(App(config: config));
}

Future<FirebaseMessaging?> _initializeFirebase(Talker talker) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      handlePushNotificationInBackground,
    );
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

Future<SupabaseClient?> _initializeSupabase(Map<String, String> env) async {
  final url = env['SUPABASE_URL']?.trim();
  final publishableKey = env['SUPABASE_PUBLISHABLE_KEY']?.trim();
  if (url == null ||
      url.isEmpty ||
      publishableKey == null ||
      publishableKey.isEmpty) {
    return null;
  }

  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  return Supabase.instance.client;
}

AppEnvironment _resolveEnvironment(Map<String, String> env) {
  final rawEnvironment = env['APP_ENV']?.trim().toLowerCase();
  return switch (rawEnvironment) {
    'prod' || 'production' => AppEnvironment.prod,
    'local' => AppEnvironment.local,
    _ => AppEnvironment.dev,
  };
}
