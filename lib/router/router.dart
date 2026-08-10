import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/router/router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/',
      page: MainRoute.page,
      children: [
        AutoRoute(path: 'chats', page: ChatsRoute.page),
        AutoRoute(path: 'friends', page: FriendsRoute.page),
        AutoRoute(path: 'profile', page: ProfileRoute.page),
      ],
    ),
    CustomRoute(
      path: '/chat',
      page: ChatRoute.page,
      transitionsBuilder: _slideRightWithFade,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
    ),

    CustomRoute(
      path: '/new-chat',
      page: NewChatRoute.page,
      transitionsBuilder: _slideRightWithFade,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
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
      child: FadeTransition(
        opacity: curvedAnimation,
        child: child,
      ),
    );
  }
}
