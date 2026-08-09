// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i7;
import 'package:flutter/material.dart' as _i8;
import 'package:yap_chat/features/chat/view/chat_page.dart' as _i1;
import 'package:yap_chat/features/chats/models/chat.dart' as _i9;
import 'package:yap_chat/features/chats/view/chats_page.dart' as _i2;
import 'package:yap_chat/features/friends/view/friends_page.dart' as _i3;
import 'package:yap_chat/features/main/view/main_page.dart' as _i4;
import 'package:yap_chat/features/new_chat/view/new_chat_page.dart' as _i5;
import 'package:yap_chat/features/profile/view/profile_page.dart' as _i6;

/// generated route for
/// [_i1.ChatPage]
class ChatRoute extends _i7.PageRouteInfo<ChatRouteArgs> {
  ChatRoute({
    _i8.Key? key,
    required _i9.Chat chat,
    List<_i7.PageRouteInfo>? children,
  }) : super(
         ChatRoute.name,
         args: ChatRouteArgs(key: key, chat: chat),
         initialChildren: children,
       );

  static const String name = 'ChatRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return _i1.ChatPage(key: args.key, chat: args.chat);
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chat});

  final _i8.Key? key;

  final _i9.Chat chat;

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
/// [_i2.ChatsPage]
class ChatsRoute extends _i7.PageRouteInfo<void> {
  const ChatsRoute({List<_i7.PageRouteInfo>? children})
    : super(ChatsRoute.name, initialChildren: children);

  static const String name = 'ChatsRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i2.ChatsPage();
    },
  );
}

/// generated route for
/// [_i3.FriendsPage]
class FriendsRoute extends _i7.PageRouteInfo<void> {
  const FriendsRoute({List<_i7.PageRouteInfo>? children})
    : super(FriendsRoute.name, initialChildren: children);

  static const String name = 'FriendsRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i3.FriendsPage();
    },
  );
}

/// generated route for
/// [_i4.MainPage]
class MainRoute extends _i7.PageRouteInfo<void> {
  const MainRoute({List<_i7.PageRouteInfo>? children})
    : super(MainRoute.name, initialChildren: children);

  static const String name = 'MainRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i4.MainPage();
    },
  );
}

/// generated route for
/// [_i5.NewChatPage]
class NewChatRoute extends _i7.PageRouteInfo<void> {
  const NewChatRoute({List<_i7.PageRouteInfo>? children})
    : super(NewChatRoute.name, initialChildren: children);

  static const String name = 'NewChatRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i5.NewChatPage();
    },
  );
}

/// generated route for
/// [_i6.ProfilePage]
class ProfileRoute extends _i7.PageRouteInfo<void> {
  const ProfileRoute({List<_i7.PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i6.ProfilePage();
    },
  );
}
