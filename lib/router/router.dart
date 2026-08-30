import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/repositories/auth/oauth_attempt_coordinator.dart';
import 'package:yap_chat/router/router.gr.dart';

List<NavigatorObserver> createAppNavigatorObservers() => [
  HeroController(),
  AutoRouteObserver(),
];

/// Keeps OAuth protocol callbacks out of the application's navigation stack.
///
/// Supabase observes the same platform link independently. At cold start the
/// app still needs its default route while Supabase exchanges the callback;
/// during an already running session the router must leave the current stack
/// untouched.
DeepLink resolveAppDeepLink(
  PlatformDeepLink deepLink, {
  required String authRedirectUrl,
}) {
  if (!isConfiguredAuthCallback(deepLink.uri, authRedirectUrl)) {
    return deepLink;
  }

  return deepLink.initial ? DeepLink.defaultPath : DeepLink.none;
}

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/',
      page: AuthGateRoute.page,
      children: [
        CustomRoute(
          path: '',
          page: SplashRoute.page,
          transitionsBuilder: _fade,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'welcome',
          page: WelcomeRoute.page,
          transitionsBuilder: _fade,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'profile-setup',
          page: ProfileSetupRoute.page,
          transitionsBuilder: _fade,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'auth-failure',
          page: AuthFailureRoute.page,
          transitionsBuilder: _fade,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'app',
          page: MainRoute.page,
          transitionsBuilder: _fade,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
          children: [
            AutoRoute(path: 'chats', page: ChatsRoute.page),
            AutoRoute(path: 'friends', page: FriendsRoute.page),
            AutoRoute(path: 'profile', page: ProfileRoute.page),
          ],
        ),
        CustomRoute(
          path: 'chat',
          page: ChatRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'new-chat',
          page: NewChatRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'add-friend',
          page: AddFriendRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'add-friend-by-username',
          page: AddFriendByUsernameRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'add-friend-by-phone',
          page: AddFriendByPhoneRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 150),
        ),
        CustomRoute(
          path: 'user-profile',
          page: ViewedProfileRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 240),
          reverseDuration: const Duration(milliseconds: 180),
        ),
        CustomRoute(
          path: 'user-friends',
          page: UserFriendsRoute.page,
          transitionsBuilder: _slideRightWithFade,
          duration: const Duration(milliseconds: 220),
          reverseDuration: const Duration(milliseconds: 170),
        ),
      ],
    ),
  ];

  static Widget _slideRightWithFade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(curvedAnimation),
      child: FadeTransition(opacity: curvedAnimation, child: child),
    );
  }

  static Widget _fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
