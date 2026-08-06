import 'package:auto_route/auto_route.dart';
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
  ];
}
