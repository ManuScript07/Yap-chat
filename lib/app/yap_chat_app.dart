import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yap_chat/app/chat_navigation_coordinator.dart';
import 'package:yap_chat/app/app_connection_coordinator.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/app_initializer.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/app/permission_reminder_coordinator.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/notifications/notifications.dart';
import 'package:yap_chat/features/profile/profile.dart';
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
  bool _permissionReminderScheduled = false;
  bool _isForeground = true;
  late final ChatNavigationCoordinator _chatNavigator;
  bool _dependenciesInitialized = false;
  String? _activeUserId;
  final Set<String> _openingNotificationChatIds = <String>{};

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
      isPeerVisible: _isPeerVisible,
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
    final locationTracking = context.read<LocationTrackingCoordinator>();
    final notifications = context.read<NotificationsCubit>();
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      unawaited(connections.setForeground(true));
      unawaited(locationTracking.setForeground(true));
      unawaited(notifications.setAppForeground(true));
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _isForeground = false;
      unawaited(notifications.setAppForeground(false));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      unawaited(connections.setForeground(false));
      unawaited(locationTracking.setForeground(false));
      unawaited(notifications.setAppForeground(false));
    }
  }

  Future<void> _restorePendingChat() async {
    final repository = context.read<ILocalMediaRepository>();
    final pendingChatId = await repository.consumePendingChatId();
    if (!mounted || pendingChatId == null) return;

    await _chatNavigator.openById(pendingChatId);
  }

  Future<void> _openNotificationChat(String conversationId) async {
    final notifications = context.read<NotificationsCubit>();
    if (notifications.state.pendingConversationId != conversationId) return;
    if (!_openingNotificationChatIds.add(conversationId)) {
      return;
    }

    try {
      // On a cold start the local notification plugin can deliver its launch
      // payload before AuthGate has mounted the authenticated router. Keep the
      // pending id until the route is actually visible instead of dropping a
      // valid tap during that short window.
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!mounted ||
            notifications.state.pendingConversationId != conversationId) {
          return;
        }

        final authRouter = await _authenticatedRouter;
        if (authRouter == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        if (notifications.state.activeConversationId == conversationId ||
            _isConversationVisible(conversationId)) {
          notifications.navigationHandled(conversationId);
          return;
        }

        await _chatNavigator.openById(conversationId);
        if (_isConversationVisible(conversationId)) {
          notifications.navigationHandled(conversationId);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _openingNotificationChatIds.remove(conversationId);
    }
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

  bool _isPeerVisible(String peerId) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return false;

    final authRouter = _authRouter;
    if (authRouter == null || authRouter.stackData.isEmpty) return false;

    final route = authRouter.stackData.last;
    if (route.name != ChatRoute.name) return false;

    return route.argsAs<ChatRouteArgs>().chat.peerId == normalizedPeerId;
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

  Future<void> _initializeNotificationsAndReminder(String userId) async {
    try {
      await context.read<NotificationsCubit>().setAuthenticatedUser(userId);
    } catch (error, stackTrace) {
      if (mounted) context.read<AppConfig>().talker.handle(error, stackTrace);
    }
    if (!mounted || _permissionReminderScheduled) return;
    _permissionReminderScheduled = true;

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || !_isForeground) return;
    final authState = context.read<AuthBloc>().state;
    if (authState.status != AuthStatus.authenticated ||
        authState.session?.userId != userId) {
      return;
    }

    final authRouter = await _authenticatedRouter;
    if (!mounted || authRouter == null) return;
    final reminderCoordinator = context.read<PermissionReminderCoordinator>();
    final reminder = await reminderCoordinator.reminderForLaunch(userId);
    if (!mounted ||
        !_isForeground ||
        reminder == null ||
        authRouter.stackData.length != 1) {
      return;
    }
    final dialogContext = authRouter.navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    switch (reminder) {
      case PermissionReminderKind.notificationsBlocked:
        await showPermissionDeniedDialog(
          dialogContext,
          title: dialogContext.l10n.notificationsPermissionReminderTitle,
          content: dialogContext.l10n.notificationsPermissionReminderContent,
          onOpenSettings: context
              .read<IPushNotificationsRepository>()
              .openAppSettings,
        );
        break;
      case PermissionReminderKind.locationServiceDisabled:
        await showPermissionDeniedDialog(
          dialogContext,
          title: dialogContext.l10n.locationDisabled,
          content: dialogContext.l10n.locationServiceReminderContent,
          onOpenSettings: context
              .read<ILocationRepository>()
              .openLocationSettings,
        );
        break;
      case PermissionReminderKind.locationPermissionPermanentlyDenied:
        await showPermissionDeniedDialog(
          dialogContext,
          title: dialogContext.l10n.locationPermissionReminderTitle,
          content: dialogContext.l10n.locationPermissionReminderContent,
          onOpenSettings: context.read<ILocationRepository>().openAppSettings,
        );
        break;
      case PermissionReminderKind.locationPermission:
        await context.read<ILocationRepository>().requestLocationAccess();
        break;
    }
    await reminderCoordinator.markPresented(userId, reminder);
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
            if (_activeUserId != userId) {
              _activeUserId = userId;
              _pendingChatRestored = false;
              context.read<AccountSessionController>().setAuthenticatedUser(
                userId,
              );
            }
            context.read<ProfileMutationCubit>().setAuthenticatedUser(userId);
            if (state.status == AuthStatus.authenticated && userId != null) {
              unawaited(
                context.read<AppConnectionCoordinator>().setAuthenticatedUser(
                  userId,
                ),
              );
              unawaited(
                context
                    .read<LocationTrackingCoordinator>()
                    .setAuthenticatedUser(userId),
              );
              unawaited(_initializeNotificationsAndReminder(userId));
            } else if (state.status == AuthStatus.unauthenticated ||
                state.status == AuthStatus.profileIncomplete ||
                state.status == AuthStatus.failure) {
              unawaited(
                context.read<AppConnectionCoordinator>().setAuthenticatedUser(
                  null,
                ),
              );
              unawaited(
                context
                    .read<LocationTrackingCoordinator>()
                    .setAuthenticatedUser(null),
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
        BlocListener<ProfileMutationCubit, ProfileMutationState>(
          listenWhen: (previous, current) =>
              previous.savedProfile != current.savedProfile &&
              current.status == ProfileMutationStatus.success,
          listener: (context, state) {
            final profile = state.savedProfile;
            if (profile != null) {
              context.read<AuthBloc>().add(AuthProfileUpdated(profile));
            }
          },
        ),
        BlocListener<NotificationsCubit, NotificationsState>(
          listenWhen: (previous, current) =>
              previous.pendingConversationId != current.pendingConversationId &&
              current.pendingConversationId != null,
          listener: (context, state) {
            final conversationId = state.pendingConversationId;
            if (conversationId != null) {
              unawaited(_openNotificationChat(conversationId));
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
            deepLinkBuilder: (deepLink) => resolveAppDeepLink(
              deepLink,
              authRedirectUrl: context.read<AppConfig>().authRedirectUrl,
            ),
          ),
        ),
      ),
    );
  }
}
