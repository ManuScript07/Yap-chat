import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatsBloc, ChatsState>(
      buildWhen: (previous, current) {
        final prevMuted = previous.chats
            .where((c) => previous.selectedChatIds.contains(c.id))
            .firstOrNull
            ?.isMuted;
        final currMuted = current.chats
            .where((c) => current.selectedChatIds.contains(c.id))
            .firstOrNull
            ?.isMuted;

        return previous.isSelectionMode != current.isSelectionMode ||
            previous.selectedChatIds.length != current.selectedChatIds.length ||
            prevMuted != currMuted;
      },
      builder: (context, state) {
        final mediaQuery = MediaQuery.of(context);
        final isLandscapeKeyboard =
            mediaQuery.orientation == Orientation.landscape &&
            mediaQuery.viewInsets.bottom > 0;
        const appBarHeight = 130.0;
        const searchBarHeight = 50.0;
        const searchBarSpacing = 16.0;
        const navigationBarHeight = 70.0;
        const navigationBarBottomOffset = 0.0;
        const snackBarSearchGap = 8.0;
        final searchBarTop =
            mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            searchBarSpacing -
            searchBarHeight;
        final hideAppBarForKeyboard =
            !state.isSelectionMode &&
            isLandscapeKeyboard &&
            searchBarTop < appBarHeight;
        final notificationSnackBarBottomMargin =
            mediaQuery.viewPadding.bottom +
            navigationBarHeight +
            navigationBarBottomOffset +
            searchBarHeight +
            searchBarSpacing +
            snackBarSearchGap;

        final selectedChats = state.chats.where(
          (chat) => state.selectedChatIds.contains(chat.id),
        );
        final firstSelectedMuted = selectedChats.firstOrNull?.isMuted ?? false;

        return ScaffoldMessenger(
          child: Builder(
            builder: (scaffoldContext) => Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: context.scaffoldBackgroundColor,
              extendBodyBehindAppBar: true,
              appBar: hideAppBarForKeyboard
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(130),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        reverseDuration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slideAnimation = Tween<Offset>(
                            begin: const Offset(0, -0.06),
                            end: Offset.zero,
                          ).animate(animation);

                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slideAnimation,
                              child: child,
                            ),
                          );
                        },
                        child: state.isSelectionMode
                            ? SelectionToolbar(
                                key: const ValueKey('selection_toolbar'),
                                selectedCount: state.selectedChatIds.length,
                                onClose: () => context.read<ChatsBloc>().add(
                                  const ChatSelectionCleared(),
                                ),
                                isMuted: firstSelectedMuted,
                                onToggleNotifications: () {
                                  context.read<ChatsBloc>().add(
                                    const ChatsMuteToggled(),
                                  );
                                  showAppSnackBar(
                                    scaffoldContext,
                                    message: firstSelectedMuted
                                        ? context.l10n.chatsNotificationsEnabled
                                        : context
                                              .l10n
                                              .chatsNotificationsDisabled,
                                    type: SnackBarType.info,
                                    bottomMargin:
                                        notificationSnackBarBottomMargin,
                                  );
                                },
                                onMarkAsRead: () => context
                                    .read<ChatsBloc>()
                                    .add(const ChatsMarkedAsRead()),
                                onDelete: () async {
                                  final count = state.selectedChatIds.length;
                                  final confirmed =
                                      await showConfirmationDialog(
                                        context,
                                        title: context.l10n.chatsDeleteTitle(
                                          count,
                                        ),
                                        content: context.l10n
                                            .chatsDeleteConfirmation(count),
                                        confirmLabel:
                                            context.l10n.chatActionDelete,
                                      );
                                  if (confirmed == true && context.mounted) {
                                    context.read<ChatsBloc>().add(
                                      const ChatsDeleted(),
                                    );
                                  }
                                },
                              )
                            : PrimaryAppBar(
                                key: const ValueKey('primary_app_bar'),
                                title: context.l10n.navChats,
                                actionIcon: Icons.add_comment_rounded,
                                onActionPressed: () {
                                  FocusScope.of(context).unfocus();
                                  final authRouter = context.router.root
                                      .innerRouterOf<StackRouter>(
                                        AuthGateRoute.name,
                                      );
                                  if (authRouter != null) {
                                    unawaited(
                                      authRouter.push(const NewChatRoute()),
                                    );
                                  }
                                },
                              ),
                      ),
                    ),
              body: const _ChatsBody(),
            ),
          ),
        );
      },
    );
  }
}

class _ChatsBody extends StatelessWidget {
  const _ChatsBody();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    debugPrint('''
════════ CHAT LAYOUT ════════
padding.bottom: ${mediaQuery.padding.bottom}
viewPadding.bottom: ${mediaQuery.viewPadding.bottom}
viewInsets.bottom: ${mediaQuery.viewInsets.bottom}
size.height: ${mediaQuery.size.height}
═════════════════════════════
''');

    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    final systemBottomPadding = mediaQuery.viewPadding.bottom;

    const navBarHeight = 70.0;
    const navBarBottomOffset = 16.0;
    const searchBarSpacing = 16.0;
    const searchBarHeight = 50.0;
    const contentExtraPadding = 16.0;

    final navigationSpace =
        systemBottomPadding + navBarBottomOffset + navBarHeight;

    final searchBarBottomOffset = isKeyboardOpen
        ? keyboardHeight + searchBarSpacing
        : navigationSpace + searchBarSpacing;

    final contentBottomPadding =
        searchBarBottomOffset + searchBarHeight + contentExtraPadding;

    final glowBottomOffset = isKeyboardOpen ? keyboardHeight : 0.0;

    final isSelectionMode = context.select<ChatsBloc, bool>(
      (bloc) => bloc.state.isSelectionMode,
    );

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        _ChatsContent(bottomPadding: contentBottomPadding),

        AnimatedPositioned(
          duration: Duration.zero,
          curve: Curves.easeOutQuad,
          left: 0,
          right: 0,
          bottom: glowBottomOffset,
          child: const BottomAmbientGlow(),
        ),

        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
          left: 0,
          right: 0,
          bottom: isSelectionMode ? -100 : searchBarBottomOffset,
          child: GlassSearchBar(
            hintText: context.l10n.searchHintChats,
            onChanged: (value) {
              context.read<ChatsBloc>().add(ChatsSearchChanged(value));
            },
          ),
        ),
      ],
    );
  }
}

class _ChatsContent extends StatelessWidget {
  const _ChatsContent({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatsBloc, ChatsState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.filteredChats != current.filteredChats ||
          previous.searchQuery != current.searchQuery ||
          previous.selectedChatIds != current.selectedChatIds ||
          previous.isSelectionMode != current.isSelectionMode,
      builder: (context, state) {
        switch (state.status) {
          case ChatsStatus.initial:
          case ChatsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case ChatsStatus.failure:
            return Center(child: Text(context.l10n.failedToLoadChats));
          case ChatsStatus.success:
            if (state.filteredChats.isEmpty) {
              final isSearchResultEmpty = state.searchQuery.trim().isNotEmpty;

              return AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuad,
                padding: EdgeInsets.only(top: 130, bottom: bottomPadding),
                child: EmptyChatState(
                  showImage: !isSearchResultEmpty,
                  message: isSearchResultEmpty
                      ? context.l10n.chatsNoSearchResults
                      : context.l10n.noChats,
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.only(top: 130, bottom: bottomPadding),
              itemCount: state.filteredChats.length,
              itemBuilder: (context, index) {
                final chat = state.filteredChats[index];
                final isSelected = state.selectedChatIds.contains(chat.id);

                return ChatListItem(
                  key: ValueKey(chat.id),
                  chat: chat,
                  isSelected: isSelected,
                  onTap: () {
                    FocusScope.of(context).unfocus();

                    if (state.isSelectionMode) {
                      context.read<ChatsBloc>().add(
                        ChatSelectionToggled(chat.id),
                      );
                    } else {
                      unawaited(
                        context.read<ChatNavigationCoordinator>().open(chat),
                      );
                    }
                  },
                  onLongPress: () {
                    if (!state.isSelectionMode) {
                      context.read<ChatsBloc>().add(
                        ChatSelectionToggled(chat.id),
                      );
                    }
                  },
                );
              },
            );
        }
      },
    );
  }
}
