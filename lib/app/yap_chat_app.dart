import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/app_initializer.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/ui/ui.dart';

/// Корневой виджет приложения: держит роутер и конфигурацию MaterialApp.
class App extends StatefulWidget {
  const App({
    super.key,
    required this.config,
  });

  final AppConfig config;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _appRouter = AppRouter();

  @override
  Widget build(BuildContext context) {
    return AppInitializer(
      config: widget.config,
      child: MaterialApp.router(
        title: 'Yap chat',
        theme: theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _appRouter.config(),
      ),
    );
  }
}
