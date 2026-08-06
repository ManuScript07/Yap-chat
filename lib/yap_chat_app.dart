import 'package:flutter/material.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/theme/theme.dart';

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
      title: 'Yap',
      theme: theme,
      routerConfig: _appRouter.config(),
    );
  }
}
