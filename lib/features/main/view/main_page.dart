import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/core/core.dart';

@RoutePage()
class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {

    return AutoTabsRouter(
      routes: const [
        ChatsRoute(),
        FriendsRoute(),
        ProfileRoute(),
      ],
      transitionBuilder: (context, child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        const int chatsTabIndex = 0;

        final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

        return PopScope(
          canPop: tabsRouter.activeIndex == chatsTabIndex && !isKeyboardOpen,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            if (isKeyboardOpen) {
              FocusScope.of(context).unfocus();
              return;
            }

            if (tabsRouter.activeIndex != chatsTabIndex) {
              tabsRouter.setActiveIndex(chatsTabIndex);
            }
          },
          child: Scaffold(
            // сжатие главного экрана.
            resizeToAvoidBottomInset: false,

            extendBody: true,
            body: Stack(
              children: [
                child,
              ],
            ),
            bottomNavigationBar: FloatingNavigationBar(
              activeIndex: tabsRouter.activeIndex,
              onTap: tabsRouter.setActiveIndex,
              items: [
                FloatingNavigationBarItem(
                  icon: Icons.sms_outlined,
                  activeIcon: Icons.sms_rounded,
                  label: context.l10n.navChats,
                ),
                FloatingNavigationBarItem(
                  icon: Icons.mood_outlined,
                  activeIcon: Icons.emoji_emotions,
                  label: context.l10n.navFriends,
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