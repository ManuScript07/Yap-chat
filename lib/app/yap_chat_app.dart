import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/app/app_connection_coordinator.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/app_initializer.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

/// Корневой виджет приложения: держит роутер и конфигурацию MaterialApp.
class App extends StatefulWidget {
  const App({super.key, required this.config});

  final AppConfig config;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _appRouter = AppRouter();

  @override
  void dispose() {
    unawaited(widget.config.database.close());
    super.dispose();
  }

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

class _AppContentState extends State<_AppContent> with WidgetsBindingObserver {
  bool _pendingChatRestored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final connections = context.read<AppConnectionCoordinator>();
    if (state == AppLifecycleState.resumed) {
      unawaited(connections.setForeground(true));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(connections.setForeground(false));
    }
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
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.session?.userId != current.session?.userId,
      listener: (context, state) {
        final userId = state.session?.userId;
        if (state.status == AuthStatus.authenticated && userId != null) {
          unawaited(
            context.read<AppConnectionCoordinator>().setAuthenticatedUser(
              userId,
            ),
          );
        } else if (state.status == AuthStatus.unauthenticated ||
            state.status == AuthStatus.profileIncomplete ||
            state.status == AuthStatus.failure) {
          unawaited(
            context.read<AppConnectionCoordinator>().setAuthenticatedUser(null),
          );
        }
        if (state.status != AuthStatus.authenticated) return;
        if (_pendingChatRestored) return;
        _pendingChatRestored = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _restorePendingChat();
        });
      },
      child: MaterialApp.router(
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
      ),
    );
  }
}
