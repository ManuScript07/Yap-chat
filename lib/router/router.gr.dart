// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i12;
import 'package:flutter/material.dart' as _i13;
import 'package:yap_chat/features/auth/view/auth_failure_page.dart' as _i1;
import 'package:yap_chat/features/auth/view/auth_gate_page.dart' as _i2;
import 'package:yap_chat/features/auth/view/profile_setup_page.dart' as _i9;
import 'package:yap_chat/features/auth/view/splash_page.dart' as _i10;
import 'package:yap_chat/features/auth/view/welcome_page.dart' as _i11;
import 'package:yap_chat/features/chat/view/chat_page.dart' as _i3;
import 'package:yap_chat/features/chats/data/data.dart' as _i14;
import 'package:yap_chat/features/chats/view/chats_page.dart' as _i4;
import 'package:yap_chat/features/friends/view/friends_page.dart' as _i5;
import 'package:yap_chat/features/main/view/main_page.dart' as _i6;
import 'package:yap_chat/features/new_chat/view/new_chat_page.dart' as _i7;
import 'package:yap_chat/features/profile/view/profile_page.dart' as _i8;

/// generated route for
/// [_i1.AuthFailurePage]
class AuthFailureRoute extends _i12.PageRouteInfo<void> {
  const AuthFailureRoute({List<_i12.PageRouteInfo>? children})
    : super(AuthFailureRoute.name, initialChildren: children);

  static const String name = 'AuthFailureRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i1.AuthFailurePage();
    },
  );
}

/// generated route for
/// [_i2.AuthGatePage]
class AuthGateRoute extends _i12.PageRouteInfo<void> {
  const AuthGateRoute({List<_i12.PageRouteInfo>? children})
    : super(AuthGateRoute.name, initialChildren: children);

  static const String name = 'AuthGateRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i2.AuthGatePage();
    },
  );
}

/// generated route for
/// [_i3.ChatPage]
class ChatRoute extends _i12.PageRouteInfo<ChatRouteArgs> {
  ChatRoute({
    _i13.Key? key,
    required _i14.Chat chat,
    List<_i12.PageRouteInfo>? children,
  }) : super(
         ChatRoute.name,
         args: ChatRouteArgs(key: key, chat: chat),
         initialChildren: children,
       );

  static const String name = 'ChatRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return _i3.ChatPage(key: args.key, chat: args.chat);
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chat});

  final _i13.Key? key;

  final _i14.Chat chat;

  @override
  String toString() {
    return 'ChatRouteArgs{key: $key, chat: $chat}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatRouteArgs) return false;
    return key == other.key && chat == other.chat;
  }

  @override
  int get hashCode => key.hashCode ^ chat.hashCode;
}

/// generated route for
/// [_i4.ChatsPage]
class ChatsRoute extends _i12.PageRouteInfo<void> {
  const ChatsRoute({List<_i12.PageRouteInfo>? children})
    : super(ChatsRoute.name, initialChildren: children);

  static const String name = 'ChatsRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i4.ChatsPage();
    },
  );
}

/// generated route for
/// [_i5.FriendsPage]
class FriendsRoute extends _i12.PageRouteInfo<void> {
  const FriendsRoute({List<_i12.PageRouteInfo>? children})
    : super(FriendsRoute.name, initialChildren: children);

  static const String name = 'FriendsRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i5.FriendsPage();
    },
  );
}

/// generated route for
/// [_i6.MainPage]
class MainRoute extends _i12.PageRouteInfo<void> {
  const MainRoute({List<_i12.PageRouteInfo>? children})
    : super(MainRoute.name, initialChildren: children);

  static const String name = 'MainRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i6.MainPage();
    },
  );
}

/// generated route for
/// [_i7.NewChatPage]
class NewChatRoute extends _i12.PageRouteInfo<void> {
  const NewChatRoute({List<_i12.PageRouteInfo>? children})
    : super(NewChatRoute.name, initialChildren: children);

  static const String name = 'NewChatRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i7.NewChatPage();
    },
  );
}

/// generated route for
/// [_i8.ProfilePage]
class ProfileRoute extends _i12.PageRouteInfo<void> {
  const ProfileRoute({List<_i12.PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i8.ProfilePage();
    },
  );
}

/// generated route for
/// [_i9.ProfileSetupPage]
class ProfileSetupRoute extends _i12.PageRouteInfo<void> {
  const ProfileSetupRoute({List<_i12.PageRouteInfo>? children})
    : super(ProfileSetupRoute.name, initialChildren: children);

  static const String name = 'ProfileSetupRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i9.ProfileSetupPage();
    },
  );
}

/// generated route for
/// [_i10.SplashPage]
class SplashRoute extends _i12.PageRouteInfo<void> {
  const SplashRoute({List<_i12.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i10.SplashPage();
    },
  );
}

/// generated route for
/// [_i11.WelcomePage]
class WelcomeRoute extends _i12.PageRouteInfo<void> {
  const WelcomeRoute({List<_i12.PageRouteInfo>? children})
    : super(WelcomeRoute.name, initialChildren: children);

  static const String name = 'WelcomeRoute';

  static _i12.PageInfo page = _i12.PageInfo(
    name,
    builder: (data) {
      return const _i11.WelcomePage();
    },
  );
}
