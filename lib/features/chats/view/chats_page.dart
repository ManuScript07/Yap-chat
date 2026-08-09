import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      builder: (context, state) {
        final selectedChats = state.chats
            .where((chat) => state.selectedChatIds.contains(chat.id));
        final firstSelectedMuted = selectedChats.firstOrNull?.isMuted ?? false;

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: context.scaffoldBackgroundColor,
          extendBodyBehindAppBar: true,
          appBar: state.isSelectionMode
              ? SelectionToolbar(
                  selectedCount: state.selectedChatIds.length,
                  onClose: () => context.read<ChatsBloc>().add(
                        const ChatSelectionCleared(),
                      ),
                  isMuted: firstSelectedMuted,
                  onToggleNotifications: () =>
                      context.read<ChatsBloc>().add(
                            const ChatsMuteToggled(),
                          ),
                  onMarkAsRead: () => context.read<ChatsBloc>().add(
                        const ChatsMarkedAsRead(),
                      ),
                  onDelete: () => context.read<ChatsBloc>().add(
                        const ChatsDeleted(),
                      ),
                )
              : PrimaryAppBar(
                  title: context.l10n.navChats,
                  actionIcon: Icons.add_comment_rounded,
                  onActionPressed: () =>
                      context.router.push(const NewChatRoute()),
                ),
          body: _ChatsBody(state: state),
        );
      },
    );
  }
}

class _ChatsBody extends StatelessWidget {
  const _ChatsBody({
    required this.state,
  });

  final ChatsState state;

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    final rawBottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final effectiveBottomPadding = math.max(rawBottomPadding, 16.0);

    const navBarHeight = 70.0;
    const navBarBottomOffset = 16.0;
    const searchBarSpacing = 16.0;
    const searchBarHeight = 50.0;

    final baseOffset =
        effectiveBottomPadding +
        navBarBottomOffset +
        navBarHeight +
        searchBarSpacing;

    final searchBarBottomOffset = isKeyboardOpen
        ? keyboardHeight + 16.0
        : baseOffset;

    final glowBottomOffset = isKeyboardOpen ? keyboardHeight : 0.0;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        _ChatsContent(
          state: state,
          bottomPadding: searchBarBottomOffset + searchBarHeight + 16,
        ),
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
          bottom: state.isSelectionMode ? -100 : searchBarBottomOffset,
          child: GlassSearchBar(
            hintText: context.l10n.searchHintChats,
            onChanged: (value) => context.read<ChatsBloc>().add(
                  ChatsSearchChanged(value),
                ),
          ),
        ),
      ],
    );
  }
}

class _ChatsContent extends StatelessWidget {
  const _ChatsContent({
    required this.state,
    required this.bottomPadding,
  });

  final ChatsState state;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case ChatsStatus.initial:
      case ChatsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ChatsStatus.failure:
        return Center(child: Text(context.l10n.failedToLoadChats));
      case ChatsStatus.success:
        if (state.filteredChats.isEmpty) {
          return Center(child: Text(context.l10n.noChats));
        }

        return ListView.builder(
          padding: EdgeInsets.only(
            top: 130,
            bottom: bottomPadding,
          ),
          itemCount: state.filteredChats.length,
          itemBuilder: (context, index) {
            final chat = state.filteredChats[index];
            final isSelected = state.selectedChatIds.contains(chat.id);

            return ChatListItem(
              chat: chat,
              isSelected: isSelected,
              onTap: () {
                if (state.isSelectionMode) {
                  context.read<ChatsBloc>().add(ChatSelectionToggled(chat.id));
                } else {
                  context.router.push(ChatRoute(chat: chat));
                }
              },
              onLongPress: () {
                if (!state.isSelectionMode) {
                  context.read<ChatsBloc>().add(ChatSelectionToggled(chat.id));
                }
              },
            );
          },
        );
    }
  }
}
