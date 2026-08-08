import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/ui/ui.dart';

class YapChatApp extends StatefulWidget {
  const YapChatApp({super.key});

  @override
  State<YapChatApp> createState() => _YapChatAppState();
}

class _YapChatAppState extends State<YapChatApp> {
  final _appRouter = AppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
    );
  }
}
