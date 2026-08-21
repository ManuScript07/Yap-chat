import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/app/chat_navigation_coordinator.dart';
import 'package:yap_chat/app/app_connection_coordinator.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/app_initializer.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/notifications/notifications.dart';
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
  late final ChatNavigationCoordinator _chatNavigator;
  bool _dependenciesInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesInitialized) return;
    _dependenciesInitialized = true;

    final chatsRepository = context.read<IChatsRepository>();
    final talker = context.read<AppConfig>().talker;
    _chatNavigator = ChatNavigationCoordinator(
      loadChat: chatsRepository.getChatById,
      navigateToChat: (chat) async {
        if (!mounted) return;
        final authRouter = await _authenticatedRouter;
        if (!mounted || authRouter == null) return;

        final chatRoute = ChatRoute(
          key: ValueKey('chat:${chat.id}'),
          chat: chat,
        );
        if (_hasActiveChatRoute(authRouter)) {
          unawaited(authRouter.popAndPush<Object?, Object?>(chatRoute));
        } else {
          unawaited(authRouter.push<Object?>(chatRoute));
        }
        await WidgetsBinding.instance.endOfFrame;
      },
      isConversationVisible: _isConversationVisible,
      isActive: () => mounted,
      onError: talker.handle,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final connections = context.read<AppConnectionCoordinator>();
    final notifications = context.read<NotificationsCubit>();
    if (state == AppLifecycleState.resumed) {
      unawaited(connections.setForeground(true));
      unawaited(notifications.setAppForeground(true));
      return;
    }
    if (state == AppLifecycleState.inactive) {
      unawaited(notifications.setAppForeground(false));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(connections.setForeground(false));
      unawaited(notifications.setAppForeground(false));
    }
  }

  Future<void> _restorePendingChat() async {
    final repository = context.read<ILocalMediaRepository>();
    final pendingChatId = await repository.consumePendingChatId();
    if (!mounted || pendingChatId == null) return;

    await _chatNavigator.openById(pendingChatId);
  }

  void _openNotificationChat(String conversationId) {
    final notifications = context.read<NotificationsCubit>();
    if (notifications.state.pendingConversationId != conversationId) return;

    notifications.navigationHandled(conversationId);
    if (notifications.state.activeConversationId == conversationId ||
        _isConversationVisible(conversationId)) {
      return;
    }

    unawaited(_chatNavigator.openById(conversationId));
  }

  bool _isConversationVisible(String conversationId) {
    final authRouter = _authRouter;
    if (authRouter == null) return false;

    final stack = authRouter.stackData;
    if (stack.isEmpty) return false;

    final route = stack.last;
    if (route.name != ChatRoute.name) return false;

    return route.argsAs<ChatRouteArgs>().chat.id == conversationId;
  }

  StackRouter? get _authRouter =>
      widget.router.innerRouterOf<StackRouter>(AuthGateRoute.name);

  Future<StackRouter?> get _authenticatedRouter async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final router = _authRouter;
      if (router != null &&
          router.stackData.isNotEmpty &&
          router.stackData.first.name == MainRoute.name) {
        return router;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  bool _hasActiveChatRoute(StackRouter authRouter) {
    final stack = authRouter.stackData;
    return stack.isNotEmpty && stack.last.name == ChatRoute.name;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
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
              unawaited(
                context.read<NotificationsCubit>().setAuthenticatedUser(userId),
              );
            } else if (state.status == AuthStatus.unauthenticated ||
                state.status == AuthStatus.profileIncomplete ||
                state.status == AuthStatus.failure) {
              unawaited(
                context.read<AppConnectionCoordinator>().setAuthenticatedUser(
                  null,
                ),
              );
              unawaited(
                context.read<NotificationsCubit>().setAuthenticatedUser(null),
              );
            }
            if (state.status != AuthStatus.authenticated) return;
            if (_pendingChatRestored) return;
            _pendingChatRestored = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _restorePendingChat();
            });
          },
        ),
        BlocListener<NotificationsCubit, NotificationsState>(
          listenWhen: (previous, current) =>
              previous.pendingConversationId != current.pendingConversationId &&
              current.pendingConversationId != null,
          listener: (context, state) {
            final conversationId = state.pendingConversationId;
            if (conversationId != null) {
              _openNotificationChat(conversationId);
            }
          },
        ),
      ],
      child: RepositoryProvider<ChatNavigationCoordinator>.value(
        value: _chatNavigator,
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
          routerConfig: widget.router.config(
            navigatorObservers: createAppNavigatorObservers,
          ),
        ),
      ),
    );
  }
}
