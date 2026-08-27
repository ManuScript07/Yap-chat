// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i15;
import 'package:flutter/material.dart' as _i16;
import 'package:yap_chat/features/auth/view/auth_failure_page.dart' as _i4;
import 'package:yap_chat/features/auth/view/auth_gate_page.dart' as _i5;
import 'package:yap_chat/features/auth/view/profile_setup_page.dart' as _i12;
import 'package:yap_chat/features/auth/view/splash_page.dart' as _i13;
import 'package:yap_chat/features/auth/view/welcome_page.dart' as _i14;
import 'package:yap_chat/features/chat/view/chat_page.dart' as _i6;
import 'package:yap_chat/features/chats/data/data.dart' as _i17;
import 'package:yap_chat/features/chats/view/chats_page.dart' as _i7;
import 'package:yap_chat/features/friends/view/add_friend_by_phone_page.dart'
    as _i1;
import 'package:yap_chat/features/friends/view/add_friend_by_username_page.dart'
    as _i2;
import 'package:yap_chat/features/friends/view/add_friend_page.dart' as _i3;
import 'package:yap_chat/features/friends/view/friends_page.dart' as _i8;
import 'package:yap_chat/features/main/view/main_page.dart' as _i9;
import 'package:yap_chat/features/new_chat/view/new_chat_page.dart' as _i10;
import 'package:yap_chat/features/profile/view/profile_page.dart' as _i11;

/// generated route for
/// [_i1.AddFriendByPhonePage]
class AddFriendByPhoneRoute extends _i15.PageRouteInfo<void> {
  const AddFriendByPhoneRoute({List<_i15.PageRouteInfo>? children})
    : super(AddFriendByPhoneRoute.name, initialChildren: children);

  static const String name = 'AddFriendByPhoneRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i1.AddFriendByPhonePage();
    },
  );
}

/// generated route for
/// [_i2.AddFriendByUsernamePage]
class AddFriendByUsernameRoute extends _i15.PageRouteInfo<void> {
  const AddFriendByUsernameRoute({List<_i15.PageRouteInfo>? children})
    : super(AddFriendByUsernameRoute.name, initialChildren: children);

  static const String name = 'AddFriendByUsernameRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i2.AddFriendByUsernamePage();
    },
  );
}

/// generated route for
/// [_i3.AddFriendPage]
class AddFriendRoute extends _i15.PageRouteInfo<void> {
  const AddFriendRoute({List<_i15.PageRouteInfo>? children})
    : super(AddFriendRoute.name, initialChildren: children);

  static const String name = 'AddFriendRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i3.AddFriendPage();
    },
  );
}

/// generated route for
/// [_i4.AuthFailurePage]
class AuthFailureRoute extends _i15.PageRouteInfo<void> {
  const AuthFailureRoute({List<_i15.PageRouteInfo>? children})
    : super(AuthFailureRoute.name, initialChildren: children);

  static const String name = 'AuthFailureRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i4.AuthFailurePage();
    },
  );
}

/// generated route for
/// [_i5.AuthGatePage]
class AuthGateRoute extends _i15.PageRouteInfo<void> {
  const AuthGateRoute({List<_i15.PageRouteInfo>? children})
    : super(AuthGateRoute.name, initialChildren: children);

  static const String name = 'AuthGateRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i5.AuthGatePage();
    },
  );
}

/// generated route for
/// [_i6.ChatPage]
class ChatRoute extends _i15.PageRouteInfo<ChatRouteArgs> {
  ChatRoute({
    _i16.Key? key,
    required _i17.Chat chat,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ChatRoute.name,
         args: ChatRouteArgs(key: key, chat: chat),
         initialChildren: children,
       );

  static const String name = 'ChatRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return _i6.ChatPage(key: args.key, chat: args.chat);
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chat});

  final _i16.Key? key;

  final _i17.Chat chat;

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
/// [_i7.ChatsPage]
class ChatsRoute extends _i15.PageRouteInfo<void> {
  const ChatsRoute({List<_i15.PageRouteInfo>? children})
    : super(ChatsRoute.name, initialChildren: children);

  static const String name = 'ChatsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i7.ChatsPage();
    },
  );
}

/// generated route for
/// [_i8.FriendsPage]
class FriendsRoute extends _i15.PageRouteInfo<void> {
  const FriendsRoute({List<_i15.PageRouteInfo>? children})
    : super(FriendsRoute.name, initialChildren: children);

  static const String name = 'FriendsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i8.FriendsPage();
    },
  );
}

/// generated route for
/// [_i9.MainPage]
class MainRoute extends _i15.PageRouteInfo<void> {
  const MainRoute({List<_i15.PageRouteInfo>? children})
    : super(MainRoute.name, initialChildren: children);

  static const String name = 'MainRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i9.MainPage();
    },
  );
}

/// generated route for
/// [_i10.NewChatPage]
class NewChatRoute extends _i15.PageRouteInfo<void> {
  const NewChatRoute({List<_i15.PageRouteInfo>? children})
    : super(NewChatRoute.name, initialChildren: children);

  static const String name = 'NewChatRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i10.NewChatPage();
    },
  );
}

/// generated route for
/// [_i11.ProfilePage]
class ProfileRoute extends _i15.PageRouteInfo<void> {
  const ProfileRoute({List<_i15.PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i11.ProfilePage();
    },
  );
}

/// generated route for
/// [_i12.ProfileSetupPage]
class ProfileSetupRoute extends _i15.PageRouteInfo<void> {
  const ProfileSetupRoute({List<_i15.PageRouteInfo>? children})
    : super(ProfileSetupRoute.name, initialChildren: children);

  static const String name = 'ProfileSetupRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i12.ProfileSetupPage();
    },
  );
}

/// generated route for
/// [_i13.SplashPage]
class SplashRoute extends _i15.PageRouteInfo<void> {
  const SplashRoute({List<_i15.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i13.SplashPage();
    },
  );
}

/// generated route for
/// [_i14.WelcomePage]
class WelcomeRoute extends _i15.PageRouteInfo<void> {
  const WelcomeRoute({List<_i15.PageRouteInfo>? children})
    : super(WelcomeRoute.name, initialChildren: children);

  static const String name = 'WelcomeRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i14.WelcomePage();
    },
  );
}
