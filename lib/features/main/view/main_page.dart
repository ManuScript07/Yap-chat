import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/nearby/nearby.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ChatsBloc>(
          create: (context) =>
              ChatsBloc(chatsRepository: context.read<IChatsRepository>())
                ..add(const ChatsLoadStarted()),
        ),
        BlocProvider<FriendsBloc>(
          create: (context) =>
              FriendsBloc(repository: context.read<IFriendsRepository>())
                ..add(const FriendsLoadStarted()),
        ),
        BlocProvider<NearbyCubit>(
          create: (context) => NearbyCubit(
            repository: context.read<INearbyRepository>(),
            locationRepository: context.read<ILocationRepository>(),
            locationTrackingCoordinator: context
                .read<LocationTrackingCoordinator>(),
            accountSessionController: context.read<AccountSessionController>(),
            blocklistRepository: context.read<IBlocklistRepository>(),
            profileFriendsRepository:
                context.read<IFriendsRepository>() as IProfileFriendsRepository,
          ),
        ),
      ],
      child: const _MainView(),
    );
  }
}

class _MainView extends StatelessWidget {
  const _MainView();

  @override
  Widget build(BuildContext context) {
    const chatsTabIndex = 0;

    return AutoTabsRouter(
      routes: const [
        ChatsRoute(),
        NearbyPeopleRoute(),
        FriendsRoute(),
        ProfileRoute(),
      ],
      transitionBuilder: (context, child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);

        final rootMediaQuery = MediaQuery.of(context);

        final isKeyboardOpen = rootMediaQuery.viewInsets.bottom > 0;

        final isSelectionMode = context.select<ChatsBloc, bool>(
          (bloc) => bloc.state.isSelectionMode,
        );
        final unreadChatsCount = context.select<ChatsBloc, int>(
          (bloc) => bloc.state.chats
              .where((chat) => !chat.isMuted)
              .fold(0, (total, chat) => total + chat.unreadCount),
        );
        final incomingFriendRequestsCount = context.select<FriendsBloc, int>(
          (bloc) => bloc.state.incomingRequestCount,
        );

        return PopScope(
          canPop:
              tabsRouter.activeIndex == chatsTabIndex &&
              !isKeyboardOpen &&
              !isSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            if (isKeyboardOpen) {
              FocusManager.instance.primaryFocus?.unfocus();
              FocusScope.of(context).unfocus();
              return;
            }

            if (tabsRouter.activeIndex == chatsTabIndex && isSelectionMode) {
              context.read<ChatsBloc>().add(const ChatSelectionCleared());
              return;
            }

            if (tabsRouter.activeIndex != chatsTabIndex) {
              tabsRouter.setActiveIndex(chatsTabIndex);
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,

            body: MediaQuery(
              data: rootMediaQuery,
              child: Stack(children: [child]),
            ),

            bottomNavigationBar: FloatingNavigationBar(
              activeIndex: tabsRouter.activeIndex,
              onTap: tabsRouter.setActiveIndex,
              items: [
                FloatingNavigationBarItem(
                  icon: Icons.sms_outlined,
                  activeIcon: Icons.sms_rounded,
                  label: context.l10n.navChats,
                  unreadCount: unreadChatsCount,
                ),
                FloatingNavigationBarItem(
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label: context.l10n.navNearby,
                ),
                FloatingNavigationBarItem(
                  icon: Icons.mood_outlined,
                  activeIcon: Icons.emoji_emotions,
                  label: context.l10n.navFriends,
                  unreadCount: incomingFriendRequestsCount,
                ),
                FloatingNavigationBarItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: context.l10n.navProfile,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
