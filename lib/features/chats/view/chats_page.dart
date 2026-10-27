import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatsBloc, ChatsState>(
      buildWhen: (previous, current) =>
          previous.isSelectionMode != current.isSelectionMode ||
          previous.selectedChatIds.length != current.selectedChatIds.length ||
          previous.hasMutedSelection != current.hasMutedSelection ||
          previous.isBulkActionInProgress != current.isBulkActionInProgress,
      builder: (context, state) {
        final mediaQuery = MediaQuery.of(context);
        final isLandscapeKeyboard =
            mediaQuery.orientation == Orientation.landscape &&
            mediaQuery.viewInsets.bottom > 0;
        const appBarHeight = 130.0;
        const searchBarHeight = 50.0;
        const searchBarSpacing = 16.0;
        const notificationSnackBarBottomMargin = 156.0;
        final searchBarTop =
            mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            searchBarSpacing -
            searchBarHeight;
        final hideAppBarForKeyboard =
            !state.isSelectionMode &&
            isLandscapeKeyboard &&
            searchBarTop < appBarHeight;

        return ScaffoldMessenger(
          child: Builder(
            builder: (scaffoldContext) => BlocListener<ChatsBloc, ChatsState>(
              listenWhen: (previous, current) =>
                  previous.feedbackId != current.feedbackId &&
                  current.feedback != null,
              listener: (context, actionState) {
                final action = actionState.feedbackAction;
                final selectionLimit =
                    actionState.feedback ==
                    ChatsBulkActionFeedback.selectionLimit;
                if (action == null && !selectionLimit) return;
                final isSuccess =
                    actionState.feedback == ChatsBulkActionFeedback.success;
                final message = selectionLimit
                    ? context.l10n.chatsSelectionLimit(
                        ChatBulkSelection.maximum,
                      )
                    : isSuccess
                    ? switch (action) {
                        ChatsBulkAction.toggleMute =>
                          actionState.feedbackIsMuted == true
                              ? context.l10n.chatsNotificationsDisabled
                              : context.l10n.chatsNotificationsEnabled,
                        ChatsBulkAction.delete =>
                          context.l10n.chatsActionCompleted,
                        ChatsBulkAction.markRead =>
                          context.l10n.chatsActionCompleted,
                        null => context.l10n.chatsActionFailed,
                      }
                    : context.l10n.chatsActionFailed;
                showAppSnackBar(
                  scaffoldContext,
                  message: message,
                  type: isSuccess ? SnackBarType.success : SnackBarType.error,
                  bottomMargin: notificationSnackBarBottomMargin,
                );
              },
              child: Scaffold(
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
                                  enableNotifications: state.hasMutedSelection,
                                  isLoading: state.isBulkActionInProgress,
                                  onToggleNotifications: () {
                                    context.read<ChatsBloc>().add(
                                      const ChatsMuteToggled(),
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
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
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

class _ChatsContent extends StatefulWidget {
  const _ChatsContent({required this.bottomPadding});

  final double bottomPadding;

  @override
  State<_ChatsContent> createState() => _ChatsContentState();
}

class _ChatsContentState extends State<_ChatsContent> {
  final _scroll = ScrollController();
  final _rows = <String, BuildContext>{};
  bool _viewportScheduled = false;
  String _query = '';
  double _mainOffset = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleViewport() {
    if (_viewportScheduled) return;
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final bloc = context.read<ChatsBloc>();
      if (!bloc.state.isPaginated) return;
      final visible = <String>{};
      final screen = MediaQuery.sizeOf(context).height;
      for (final entry in _rows.entries) {
        final box = entry.value.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          final top = box.localToGlobal(Offset.zero).dy;
          if (top + box.size.height >= -100 && top <= screen + 100) {
            visible.add(entry.key);
          }
        }
      }
      bloc.add(ChatsVisibleIdsChanged(visible));
      final state = bloc.state;
      if (_scroll.position.extentAfter < 400 &&
          state.hasMoreChats &&
          (!state.isLoadingMore || state.hasMoreCached) &&
          (state.paginationError == null || state.hasMoreCached)) {
        bloc.add(const ChatsLoadMoreRequested());
      }
    });
  }

  void _preserveAnchor(ChatsState state) {
    if (!_scroll.hasClients) return;
    if (_query != state.searchQuery) {
      if (_query.isEmpty) _mainOffset = _scroll.offset;
      _query = state.searchQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (_query.isEmpty ? _mainOffset : 0.0).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
      return;
    }
    if (_scroll.offset <= 1 || _scroll.position.isScrollingNotifier.value) {
      return;
    }
    String? anchor;
    double? y;
    for (final entry in _rows.entries) {
      final box = entry.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > 130 && (y == null || top < y)) {
        anchor = entry.key;
        y = top;
      }
    }
    if (anchor == null) return;
    final id = anchor, oldY = y!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _scroll.position.isScrollingNotifier.value) {
        return;
      }
      final box = _rows[id]?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final delta = box.localToGlobal(Offset.zero).dy - oldY;
      if (delta.abs() > .5) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatsBloc, ChatsState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.filteredChats != current.filteredChats ||
          previous.searchQuery != current.searchQuery ||
          previous.hasMoreChats != current.hasMoreChats ||
          previous.isLoadingMore != current.isLoadingMore ||
          previous.paginationError != current.paginationError ||
          previous.selectedChatIds != current.selectedChatIds ||
          previous.isSelectionMode != current.isSelectionMode,
      builder: (context, state) {
        _preserveAnchor(state);
        _scheduleViewport();
        final bottomPadding = widget.bottomPadding;
        switch (state.status) {
          case ChatsStatus.initial:
          case ChatsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case ChatsStatus.failure:
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.failedToLoadChats),
                  if (state.isPaginated)
                    TextButton(
                      onPressed: () => context.read<ChatsBloc>().add(
                        const ChatsLoadMoreRequested(retry: true),
                      ),
                      child: Text(context.l10n.repeat),
                    ),
                ],
              ),
            );
          case ChatsStatus.success:
            if (state.filteredChats.isEmpty) {
              final isSearchResultEmpty = state.searchQuery.trim().isNotEmpty;

              return AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuad,
                padding: EdgeInsets.only(top: 130, bottom: bottomPadding),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EmptyChatState(
                      showImage: !isSearchResultEmpty,
                      message: isSearchResultEmpty
                          ? context.l10n.chatsNoSearchResults
                          : context.l10n.noChats,
                    ),
                    if (state.isPaginated && state.hasMoreChats)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: TextButton(
                          onPressed: () => context.read<ChatsBloc>().add(
                            const ChatsLoadMoreRequested(retry: true),
                          ),
                          child: Text(context.l10n.repeat),
                        ),
                      ),
                  ],
                ),
              );
            }

            final indexes = {
              for (final e in state.filteredChats.indexed)
                'probe:${e.$2.id}': e.$1,
            };
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _scheduleViewport();
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? indexes[key.value] : null,
                padding: EdgeInsets.only(top: 130, bottom: bottomPadding),
                itemCount:
                    state.filteredChats.length +
                    (state.isPaginated &&
                            (state.hasMoreChats ||
                                state.paginationError != null)
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index == state.filteredChats.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: state.isLoadingMore
                          ? const Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Center(
                              child: TextButton(
                                onPressed: () => context.read<ChatsBloc>().add(
                                  const ChatsLoadMoreRequested(retry: true),
                                ),
                                child: Text(
                                  state.paginationError == null
                                      ? context.l10n.repeat
                                      : '${context.l10n.failedToLoadChats}. ${context.l10n.repeat}',
                                ),
                              ),
                            ),
                    );
                  }
                  final chat = state.filteredChats[index];
                  final isSelected = state.selectedChatIds.contains(chat.id);

                  return _ChatRowProbe(
                    key: ValueKey('probe:${chat.id}'),
                    onRegister: (rowContext) {
                      _rows[chat.id] = rowContext;
                      _scheduleViewport();
                    },
                    onUnregister: (rowContext) {
                      if (_rows[chat.id] == rowContext) _rows.remove(chat.id);
                    },
                    child: ChatListItem(
                      key: ValueKey(chat.id),
                      chat: chat,
                      avatarLoader: () =>
                          context.read<IChatsRepository>().resolveAvatar(chat),
                      isSelected: isSelected,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        FocusScope.of(context).unfocus();

                        if (state.isSelectionMode) {
                          context.read<ChatsBloc>().add(
                            ChatSelectionToggled(chat.id),
                          );
                        } else {
                          unawaited(
                            context.read<ChatNavigationCoordinator>().open(
                              chat,
                            ),
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
                    ),
                  );
                },
              ),
            );
        }
      },
    );
  }
}

class _ChatRowProbe extends StatefulWidget {
  const _ChatRowProbe({
    super.key,
    required this.onRegister,
    required this.onUnregister,
    required this.child,
  });
  final ValueChanged<BuildContext> onRegister, onUnregister;
  final Widget child;
  @override
  State<_ChatRowProbe> createState() => _ChatRowProbeState();
}

class _ChatRowProbeState extends State<_ChatRowProbe> {
  @override
  Widget build(BuildContext context) {
    widget.onRegister(context);
    return widget.child;
  }

  @override
  void dispose() {
    widget.onUnregister(context);
    super.dispose();
  }
}
