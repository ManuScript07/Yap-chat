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
        // Leave room for readable feedback and a retry touch target before
        // the search bar reaches the header. Waiting for overlap can leave
        // just a few pixels of usable body height in landscape with the IME.
        final minimumContentHeight =
            (mediaQuery.textScaler.scale(22) * 1.2).clamp(
              48.0,
              double.infinity,
            ) +
            16;
        final hideAppBarForKeyboard =
            !state.isSelectionMode &&
            isLandscapeKeyboard &&
            searchBarTop <
                appBarHeight + mediaQuery.padding.top + minimumContentHeight;

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
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: hideAppBarForKeyboard ? 0 : 1),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuad,
                builder: (context, headerProgress, _) => Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor: context.scaffoldBackgroundColor,
                  extendBodyBehindAppBar: true,
                  appBar: headerProgress == 0
                      ? null
                      : PreferredSize(
                          preferredSize: Size.fromHeight(130 * headerProgress),
                          child: ClipRect(
                            key: const ValueKey('chats_header_clip'),
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 130,
                              maxHeight: 130,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                reverseDuration: const Duration(
                                  milliseconds: 180,
                                ),
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
                                        key: const ValueKey(
                                          'selection_toolbar',
                                        ),
                                        selectedCount:
                                            state.selectedChatIds.length,
                                        onClose: () => context
                                            .read<ChatsBloc>()
                                            .add(const ChatSelectionCleared()),
                                        enableNotifications:
                                            state.hasMutedSelection,
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
                                          final count =
                                              state.selectedChatIds.length;
                                          final confirmed =
                                              await showConfirmationDialog(
                                                context,
                                                title: context.l10n
                                                    .chatsDeleteTitle(count),
                                                content: context.l10n
                                                    .chatsDeleteConfirmation(
                                                      count,
                                                    ),
                                                confirmLabel: context
                                                    .l10n
                                                    .chatActionDelete,
                                              );
                                          if (confirmed == true &&
                                              context.mounted) {
                                            context.read<ChatsBloc>().add(
                                              const ChatsDeleted(),
                                            );
                                          }
                                        },
                                      )
                                    : PrimaryAppBar(
                                        key: const ValueKey('primary_app_bar'),
                                        title: context.l10n.navChats,
                                        titleWidget: ConnectionStatusTitle(
                                          title: context.l10n.navChats,
                                        ),
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
                                              authRouter.push(
                                                const NewChatRoute(),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                  body: const _ChatsBody(),
                ),
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

    final glowBottomOffset = isKeyboardOpen ? keyboardHeight : 0.0;

    final isSelectionMode = context.select<ChatsBloc, bool>(
      (bloc) => bloc.state.isSelectionMode,
    );

    // Keep the original search-field motion, while feedback follows its
    // rendered position rather than jumping immediately to the target inset.
    return TweenAnimationBuilder<double>(
      tween: Tween(
        end: searchBarBottomOffset + searchBarHeight + contentExtraPadding,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutQuad,
      builder: (context, renderedContentBottom, _) => Stack(
        alignment: Alignment.bottomCenter,
        fit: StackFit.expand,
        children: [
          _ChatsContent(bottomPadding: renderedContentBottom),

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
      ),
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
      if (!mounted) return;
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
      final nearEnd = !_scroll.hasClients
          ? state.status == ChatsStatus.success && state.filteredChats.isEmpty
          : _scroll.position.extentAfter < 400;
      if (nearEnd &&
          (state.hasMoreCached ||
              (state.hasMoreRemote && !state.isRefreshing)) &&
          (!state.isLoadingMore || state.hasMoreCached) &&
          (state.loadError == null || state.hasMoreCached)) {
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
          previous.isRefreshing != current.isRefreshing ||
          previous.paginationError != current.paginationError ||
          previous.refreshError != current.refreshError ||
          previous.selectedChatIds != current.selectedChatIds ||
          previous.isSelectionMode != current.isSelectionMode,
      builder: (context, state) {
        _preserveAnchor(state);
        _scheduleViewport();
        final bottomPadding = widget.bottomPadding;
        switch (state.status) {
          case ChatsStatus.initial:
          case ChatsStatus.loading:
            return _ChatsFeedbackViewport(
              bottomPadding: bottomPadding,
              child: Center(
                child: _ChatsLoadingIndicator(key: ValueKey(state.searchQuery)),
              ),
            );
          case ChatsStatus.failure:
            return _ChatsEmptyPresentation(
              state: state,
              bottomPadding: bottomPadding,
            );
          case ChatsStatus.success:
            if (state.filteredChats.isEmpty) {
              return _ChatsEmptyPresentation(
                state: state,
                bottomPadding: bottomPadding,
              );
            }

            final indexes = {
              for (final e in state.filteredChats.indexed)
                'probe:${e.$2.id}': e.$1,
            };
            final hasConnectionStatus =
                context.read<AppConnectionStatus?>() != null;
            // The header replaces network error wording, but continuation
            // failures still need explicit retry even after a head refresh.
            // Check both errors so neither can swallow an independent failure.
            final showLoadErrorLabel =
                [state.paginationError, state.refreshError].any(
                  (error) =>
                      error != null &&
                      (!hasConnectionStatus ||
                          !AppConnectionStatus.isConnectionFailure(error)),
                );
            final hasRetryableLoadError =
                state.paginationError != null || showLoadErrorLabel;
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
                            (state.isLoadingMore || hasRetryableLoadError)
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index == state.filteredChats.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: state.isLoadingMore || state.isRefreshing
                          ? const Center(
                              child: _ChatsLoadingIndicator(compact: true),
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showLoadErrorLabel)
                                    Text(context.l10n.failedToLoadChats),
                                  const _ChatsRetryButton(),
                                ],
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

class _ChatsEmptyPresentation extends StatelessWidget {
  const _ChatsEmptyPresentation({
    required this.state,
    required this.bottomPadding,
  });

  final ChatsState state;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isSearch = state.searchQuery.trim().isNotEmpty;
    // A retained head transport error also accompanies local-only searches.
    // It says nothing about server completeness. Any page/cache/data error
    // must retain the failure presentation, including alongside network errors.
    final isSavedSearchEmpty =
        isSearch &&
        state.isPaginated &&
        state.paginationError == null &&
        AppConnectionStatus.isConnectionFailure(state.refreshError);
    final isFailure =
        state.status == ChatsStatus.failure && !isSavedSearchEmpty;
    final message = isFailure
        ? context.l10n.failedToLoadChats
        : isSavedSearchEmpty
        ? context.l10n.chatsNoSavedSearchResults
        : isSearch
        ? context.l10n.chatsNoSearchResults
        : context.l10n.noChats;
    final hasAction =
        state.isPaginated && (isFailure || state.loadError != null);
    final isBusy = state.isRefreshing || state.isLoadingMore;
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: context.colorScheme.onSurface,
    );

    return LayoutBuilder(
      builder: (context, viewport) {
        final padding = EdgeInsets.fromLTRB(
          media.padding.left + 16,
          media.padding.top,
          media.padding.right + 16,
          bottomPadding - 8,
        );
        final constraints = BoxConstraints(
          maxWidth: (viewport.maxWidth - padding.horizontal).clamp(
            0.0,
            double.infinity,
          ),
          maxHeight: (viewport.maxHeight - padding.vertical).clamp(
            0.0,
            double.infinity,
          ),
        );
        if (!isFailure && !isSearch) {
          return Padding(
            padding: padding,
            child: EmptyChatState(message: message),
          );
        }
        final actionText = TextPainter(
          text: TextSpan(
            text: context.l10n.repeat,
            style: _ChatsRetryButton.textStyle(context),
          ),
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
        )..layout();
        final actionWidth = (actionText.width + 32)
            .clamp(64.0, double.infinity)
            .toDouble();
        final actionHeight = (actionText.height + 16)
            .clamp(48.0, double.infinity)
            .toDouble();
        actionText.dispose();
        final action = SizedBox(
          width: actionWidth,
          height: actionHeight,
          child: !hasAction
              ? null
              : isBusy
              ? const Center(child: _ChatsLoadingIndicator())
              : const _ChatsRetryButton(),
        );
        final label = Text(
          message,
          key: const ValueKey('chats_empty_label'),
          style: style,
          textAlign: TextAlign.center,
        );
        // Reserve the largest label and action for every empty-search state.
        // Anchor their TOP, so a longer offline label grows downwards from
        // the same line instead of shifting the shorter online label.
        var referenceHeight = 0.0;
        for (final text in [
          context.l10n.chatsNoSearchResults,
          context.l10n.chatsNoSavedSearchResults,
          context.l10n.failedToLoadChats,
        ]) {
          final measure = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: media.textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          if (measure.height > referenceHeight) {
            referenceHeight = measure.height;
          }
          measure.dispose();
        }
        const gap = 8.0;
        final contentTop =
            ((constraints.maxHeight - referenceHeight - gap - actionHeight) / 2)
                .clamp(0.0, double.infinity);
        // Always a full-width column. Search-field geometry must not affect
        // the label width or place retry beside it. Extremely short viewports
        // scroll the column, preserving the system text scale and touch area.
        return SingleChildScrollView(
          key: const ValueKey('chats_empty_scroll'),
          // Like the chat rows, padding belongs INSIDE the scroll viewport.
          // Text can therefore pass under the existing chrome's gradient and
          // BackdropFilter instead of being cut off by an opaque-looking gap.
          padding: padding,
          physics: hasAction
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.only(top: contentTop),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  const SizedBox(height: gap),
                  Center(child: action),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Loading feedback is centered above the same rendered search-field inset.
class _ChatsFeedbackViewport extends StatelessWidget {
  const _ChatsFeedbackViewport({
    required this.bottomPadding,
    required this.child,
  });

  final double bottomPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = bottomPadding - 8;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        media.padding.left + 16,
        media.padding.top,
        media.padding.right + 16,
        bottom,
      ),
      child: child,
    );
  }
}

class _ChatsRetryButton extends StatelessWidget {
  const _ChatsRetryButton();

  static TextStyle textStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .5);

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: context.colorScheme.primary,
      foregroundColor: context.colorScheme.onPrimary,
      textStyle: textStyle(context),
      minimumSize: const Size(64, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: const StadiumBorder(),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    ),
    onPressed: () => context.read<ChatsBloc>().add(
      const ChatsLoadMoreRequested(retry: true),
    ),
    child: Text(context.l10n.repeat),
  );
}

/// Delay feedback, not cached rows. Fast SQLite/HTTP completions never flash a
/// spinner; a genuinely slow operation still has the standard compact loader.
class _ChatsLoadingIndicator extends StatefulWidget {
  const _ChatsLoadingIndicator({super.key, this.compact = false});

  final bool compact;

  @override
  State<_ChatsLoadingIndicator> createState() => _ChatsLoadingIndicatorState();
}

class _ChatsLoadingIndicatorState extends State<_ChatsLoadingIndicator> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.compact ? 24 : 36,
    child: _visible
        ? CircularProgressIndicator(strokeWidth: widget.compact ? 2.5 : 4)
        : null,
  );
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
