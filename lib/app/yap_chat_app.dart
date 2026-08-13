import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/app_initializer.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';
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
      child: _AppContent(router: _appRouter),
    );
  }
}

class _AppContent extends StatefulWidget {
  const _AppContent({required this.router});

  final AppRouter router;

  @override
  State<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends State<_AppContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePendingChat();
    });
  }

  Future<void> _restorePendingChat() async {
    final repository = context.read<ILocalMediaRepository>();
    final pendingChatId = await repository.consumePendingChatId();
    if (!mounted || pendingChatId == null) return;

    final chats = await context.read<IChatsRepository>().getChats();
    final chat = _findChat(chats, pendingChatId);
    if (!mounted || chat == null) return;

    await widget.router.push(ChatRoute(chat: chat));
  }

  Chat? _findChat(List<Chat> chats, String chatId) {
    for (final chat in chats) {
      if (chat.id == chatId) return chat;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Yap chat',
      theme: theme,
      restorationScopeId: 'yap-chat',
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: widget.router.config(),
    );
  }
}
