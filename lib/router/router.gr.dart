// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i20;
import 'package:flutter/foundation.dart' as _i21;
import 'package:flutter/material.dart' as _i23;
import 'package:yap_chat/features/auth/view/auth_failure_page.dart' as _i4;
import 'package:yap_chat/features/auth/view/auth_gate_page.dart' as _i5;
import 'package:yap_chat/features/auth/view/banned_account_page.dart' as _i6;
import 'package:yap_chat/features/auth/view/profile_setup_page.dart' as _i14;
import 'package:yap_chat/features/auth/view/splash_page.dart' as _i16;
import 'package:yap_chat/features/auth/view/welcome_page.dart' as _i19;
import 'package:yap_chat/features/chat/view/chat_page.dart' as _i7;
import 'package:yap_chat/features/chats/data/data.dart' as _i22;
import 'package:yap_chat/features/chats/view/chats_page.dart' as _i8;
import 'package:yap_chat/features/friends/view/add_friend_by_phone_page.dart'
    as _i1;
import 'package:yap_chat/features/friends/view/add_friend_by_username_page.dart'
    as _i2;
import 'package:yap_chat/features/friends/view/add_friend_page.dart' as _i3;
import 'package:yap_chat/features/friends/view/friends_page.dart' as _i9;
import 'package:yap_chat/features/main/view/main_page.dart' as _i10;
import 'package:yap_chat/features/nearby/view/nearby_people_page.dart' as _i11;
import 'package:yap_chat/features/new_chat/view/new_chat_page.dart' as _i12;
import 'package:yap_chat/features/profile/view/profile_page.dart' as _i13;
import 'package:yap_chat/features/profile/view/user_friends_page.dart' as _i17;
import 'package:yap_chat/features/profile/view/viewed_profile_page.dart'
    as _i18;
import 'package:yap_chat/features/recommendations/view/recommendations_page.dart'
    as _i15;

/// generated route for
/// [_i1.AddFriendByPhonePage]
class AddFriendByPhoneRoute extends _i20.PageRouteInfo<void> {
  const AddFriendByPhoneRoute({List<_i20.PageRouteInfo>? children})
    : super(AddFriendByPhoneRoute.name, initialChildren: children);

  static const String name = 'AddFriendByPhoneRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i1.AddFriendByPhonePage();
    },
  );
}

/// generated route for
/// [_i2.AddFriendByUsernamePage]
class AddFriendByUsernameRoute extends _i20.PageRouteInfo<void> {
  const AddFriendByUsernameRoute({List<_i20.PageRouteInfo>? children})
    : super(AddFriendByUsernameRoute.name, initialChildren: children);

  static const String name = 'AddFriendByUsernameRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i2.AddFriendByUsernamePage();
    },
  );
}

/// generated route for
/// [_i3.AddFriendPage]
class AddFriendRoute extends _i20.PageRouteInfo<void> {
  const AddFriendRoute({List<_i20.PageRouteInfo>? children})
    : super(AddFriendRoute.name, initialChildren: children);

  static const String name = 'AddFriendRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i3.AddFriendPage();
    },
  );
}

/// generated route for
/// [_i4.AuthFailurePage]
class AuthFailureRoute extends _i20.PageRouteInfo<void> {
  const AuthFailureRoute({List<_i20.PageRouteInfo>? children})
    : super(AuthFailureRoute.name, initialChildren: children);

  static const String name = 'AuthFailureRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i4.AuthFailurePage();
    },
  );
}

/// generated route for
/// [_i5.AuthGatePage]
class AuthGateRoute extends _i20.PageRouteInfo<void> {
  const AuthGateRoute({List<_i20.PageRouteInfo>? children})
    : super(AuthGateRoute.name, initialChildren: children);

  static const String name = 'AuthGateRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i5.AuthGatePage();
    },
  );
}

/// generated route for
/// [_i6.BannedAccountPage]
class BannedAccountRoute extends _i20.PageRouteInfo<void> {
  const BannedAccountRoute({List<_i20.PageRouteInfo>? children})
    : super(BannedAccountRoute.name, initialChildren: children);

  static const String name = 'BannedAccountRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i6.BannedAccountPage();
    },
  );
}

/// generated route for
/// [_i7.ChatPage]
class ChatRoute extends _i20.PageRouteInfo<ChatRouteArgs> {
  ChatRoute({
    _i21.Key? key,
    required _i22.Chat chat,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         ChatRoute.name,
         args: ChatRouteArgs(key: key, chat: chat),
         initialChildren: children,
       );

  static const String name = 'ChatRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return _i7.ChatPage(key: args.key, chat: args.chat);
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chat});

  final _i21.Key? key;

  final _i22.Chat chat;

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
/// [_i8.ChatsPage]
class ChatsRoute extends _i20.PageRouteInfo<void> {
  const ChatsRoute({List<_i20.PageRouteInfo>? children})
    : super(ChatsRoute.name, initialChildren: children);

  static const String name = 'ChatsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i8.ChatsPage();
    },
  );
}

/// generated route for
/// [_i9.FriendsPage]
class FriendsRoute extends _i20.PageRouteInfo<void> {
  const FriendsRoute({List<_i20.PageRouteInfo>? children})
    : super(FriendsRoute.name, initialChildren: children);

  static const String name = 'FriendsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i9.FriendsPage();
    },
  );
}

/// generated route for
/// [_i10.MainPage]
class MainRoute extends _i20.PageRouteInfo<void> {
  const MainRoute({List<_i20.PageRouteInfo>? children})
    : super(MainRoute.name, initialChildren: children);

  static const String name = 'MainRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i10.MainPage();
    },
  );
}

/// generated route for
/// [_i11.NearbyPeoplePage]
class NearbyPeopleRoute extends _i20.PageRouteInfo<void> {
  const NearbyPeopleRoute({List<_i20.PageRouteInfo>? children})
    : super(NearbyPeopleRoute.name, initialChildren: children);

  static const String name = 'NearbyPeopleRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i11.NearbyPeoplePage();
    },
  );
}

/// generated route for
/// [_i12.NewChatPage]
class NewChatRoute extends _i20.PageRouteInfo<void> {
  const NewChatRoute({List<_i20.PageRouteInfo>? children})
    : super(NewChatRoute.name, initialChildren: children);

  static const String name = 'NewChatRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i12.NewChatPage();
    },
  );
}

/// generated route for
/// [_i13.ProfilePage]
class ProfileRoute extends _i20.PageRouteInfo<void> {
  const ProfileRoute({List<_i20.PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i13.ProfilePage();
    },
  );
}

/// generated route for
/// [_i14.ProfileSetupPage]
class ProfileSetupRoute extends _i20.PageRouteInfo<void> {
  const ProfileSetupRoute({List<_i20.PageRouteInfo>? children})
    : super(ProfileSetupRoute.name, initialChildren: children);

  static const String name = 'ProfileSetupRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i14.ProfileSetupPage();
    },
  );
}

/// generated route for
/// [_i15.RecommendationsPage]
class RecommendationsRoute extends _i20.PageRouteInfo<void> {
  const RecommendationsRoute({List<_i20.PageRouteInfo>? children})
    : super(RecommendationsRoute.name, initialChildren: children);

  static const String name = 'RecommendationsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i15.RecommendationsPage();
    },
  );
}

/// generated route for
/// [_i16.SplashPage]
class SplashRoute extends _i20.PageRouteInfo<void> {
  const SplashRoute({List<_i20.PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i16.SplashPage();
    },
  );
}

/// generated route for
/// [_i17.UserFriendsPage]
class UserFriendsRoute extends _i20.PageRouteInfo<UserFriendsRouteArgs> {
  UserFriendsRoute({
    _i23.Key? key,
    required String userId,
    required String userName,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         UserFriendsRoute.name,
         args: UserFriendsRouteArgs(
           key: key,
           userId: userId,
           userName: userName,
         ),
         initialChildren: children,
       );

  static const String name = 'UserFriendsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<UserFriendsRouteArgs>();
      return _i17.UserFriendsPage(
        key: args.key,
        userId: args.userId,
        userName: args.userName,
      );
    },
  );
}

class UserFriendsRouteArgs {
  const UserFriendsRouteArgs({
    this.key,
    required this.userId,
    required this.userName,
  });

  final _i23.Key? key;

  final String userId;

  final String userName;

  @override
  String toString() {
    return 'UserFriendsRouteArgs{key: $key, userId: $userId, userName: $userName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UserFriendsRouteArgs) return false;
    return key == other.key &&
        userId == other.userId &&
        userName == other.userName;
  }

  @override
  int get hashCode => key.hashCode ^ userId.hashCode ^ userName.hashCode;
}

/// generated route for
/// [_i18.ViewedProfilePage]
class ViewedProfileRoute extends _i20.PageRouteInfo<ViewedProfileRouteArgs> {
  ViewedProfileRoute({
    _i23.Key? key,
    required String userId,
    String? originChatId,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         ViewedProfileRoute.name,
         args: ViewedProfileRouteArgs(
           key: key,
           userId: userId,
           originChatId: originChatId,
         ),
         initialChildren: children,
       );

  static const String name = 'ViewedProfileRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ViewedProfileRouteArgs>();
      return _i18.ViewedProfilePage(
        key: args.key,
        userId: args.userId,
        originChatId: args.originChatId,
      );
    },
  );
}

class ViewedProfileRouteArgs {
  const ViewedProfileRouteArgs({
    this.key,
    required this.userId,
    this.originChatId,
  });

  final _i23.Key? key;

  final String userId;

  final String? originChatId;

  @override
  String toString() {
    return 'ViewedProfileRouteArgs{key: $key, userId: $userId, originChatId: $originChatId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViewedProfileRouteArgs) return false;
    return key == other.key &&
        userId == other.userId &&
        originChatId == other.originChatId;
  }

  @override
  int get hashCode => key.hashCode ^ userId.hashCode ^ originChatId.hashCode;
}

/// generated route for
/// [_i19.WelcomePage]
class WelcomeRoute extends _i20.PageRouteInfo<void> {
  const WelcomeRoute({List<_i20.PageRouteInfo>? children})
    : super(WelcomeRoute.name, initialChildren: children);

  static const String name = 'WelcomeRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i19.WelcomePage();
    },
  );
}
