import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/services/media_service.dart';
import 'package:yap_chat/repositories/chat/local_media_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(isOptional: true);
  await initializeDateFormatting();

  final preferences = await SharedPreferences.getInstance();
  final talker = Talker();

  final localMediaRepository = LocalMediaRepository(
    preferences: preferences,
  );
  final lostPhotoPath = await MediaService.retrieveLostPhoto();
  if (lostPhotoPath != null) {
    final persistedPath = await localMediaRepository.persistMedia(lostPhotoPath);
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
    environment: _resolveEnvironment(dotenv.env),
    preferences: preferences,
    talker: talker,
    env: Map.unmodifiable(dotenv.env),
  );

  runApp(App(config: config));
}

AppEnvironment _resolveEnvironment(Map<String, String> env) {
  final rawEnvironment = env['APP_ENV']?.trim().toLowerCase();
  return rawEnvironment == 'prod' || rawEnvironment == 'production'
      ? AppEnvironment.prod
      : AppEnvironment.dev;
}
