import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
    final restingContentBottom =
        navigationSpace +
        searchBarSpacing +
        searchBarHeight +
        contentExtraPadding;

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
          _ChatsContent(
            bottomPadding: renderedContentBottom,
            // The IME overlays this full-screen list; touching the list hides
            // it. Keep its extent stable instead of adding a temporary tail
            // that a dismissal swipe can enter and immediately lose again.
            listBottomPadding: restingContentBottom,
            suppressEdgeStretch:
                isKeyboardOpen ||
                (renderedContentBottom - restingContentBottom).abs() > .5,
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
  const _ChatsContent({
    required this.bottomPadding,
    required this.listBottomPadding,
    required this.suppressEdgeStretch,
  });

  final double bottomPadding;
  final double listBottomPadding;
  final bool suppressEdgeStretch;

  @override
  State<_ChatsContent> createState() => _ChatsContentState();
}

class _ChatsContentState extends State<_ChatsContent>
    with SingleTickerProviderStateMixin {
  final _scroll = _ChatsScrollController();
  final _rows = <String, BuildContext>{};
  bool _viewportScheduled = false;
  String _query = '';
  double _mainOffset = 0;
  int _scrollQueryRevision = 0;
  Set<String> _mainAvatarIds = {};
  ChatsState? _displayedState, _preparingTarget;
  List<String>? _preparingPaths;
  LocalAvatarFrames? _heldFrames;
  int _presentationEpoch = 0;
  late final _rowMotion =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && _motionActive) {
          setState(() {
            _motionActive = false;
            _motionDragStart = null;
          });
        }
      });
  bool _motionActive = false;
  double? _motionDragStart;
  Map<String, double> _motionOrigins = {};
  Size? _motionViewport;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.sizeOf(context);
    if ((_motionViewport != null && _motionViewport != viewport) ||
        MediaQuery.disableAnimationsOf(context)) {
      _stopRowMotion();
    }
    _motionViewport = viewport;
  }

  void _stopRowMotion() {
    if (!_motionActive) return;
    _rowMotion.value = 1;
  }

  double _motionScrollDisplacement() =>
      _motionDragStart != null && _scroll.hasClients
      ? _scroll.offset - _motionDragStart!
      : 0;

  bool _waitingFor(ChatsState state) =>
      state.status == ChatsStatus.initial ||
      state.status == ChatsStatus.loading ||
      state.searchQuery != state.presentedQuery ||
      _preparingTarget != null;

  void _commitPresentation(ChatsState state) {
    final before = _displayedState?.filteredChats;
    final after = state.filteredChats;
    final changed =
        before != null &&
        (before.length != after.length ||
            before.indexed.any(
              (entry) =>
                  entry.$2.id != after[entry.$1].id ||
                  entry.$2.peerIsDeleted != after[entry.$1].peerIsDeleted ||
                  entry.$2.peerIsGloballyBanned !=
                      after[entry.$1].peerIsGloballyBanned,
            ));
    final scrolling =
        _scroll.hasClients && _scroll.position.isScrollingNotifier.value;
    if (changed &&
        !MediaQuery.disableAnimationsOf(context) &&
        (!scrolling || _motionActive)) {
      _motionOrigins = {
        for (final entry in _rows.entries)
          if (entry.value.findRenderObject() case final RenderBox box
              when box.attached && box.hasSize)
            entry.key: ChatListRowMotion.visualTopOf(box),
      };
      _motionActive = true;
      _motionDragStart = scrolling ? _scroll.offset : null;
      _rowMotion.forward(from: 0);
    } else if (changed && MediaQuery.disableAnimationsOf(context)) {
      _stopRowMotion();
    }
    _displayedState = state.copyWith(searchQuery: state.presentedQuery);
  }

  List<String> _incomingAvatarPaths(ChatsState state) {
    final limit = ((MediaQuery.sizeOf(context).height + 250) / 76).ceil().clamp(
      1,
      12,
    );
    final rows = state.presentedQuery.isEmpty && _mainOffset > 1
        ? state.filteredChats.where((chat) => _mainAvatarIds.contains(chat.id))
        : state.filteredChats;
    return rows
        .take(limit)
        .where(
          (chat) =>
              !_rows.containsKey(chat.id) &&
              !chat.blockedByPeer &&
              !chat.peerIsGloballyBanned &&
              !chat.peerIsDeleted &&
              (chat.avatarStoragePath != null || chat.avatarUrl != null) &&
              chat.cachedAvatarPath != null,
        )
        .map((chat) => chat.cachedAvatarPath!)
        .toSet()
        .toList();
  }

  bool _hasAvatarRevocation(ChatsState state) {
    final old = {
      for (final chat in _displayedState?.filteredChats ?? <Chat>[])
        chat.id: chat,
    };
    return state.filteredChats.any(
      (chat) =>
          old.containsKey(chat.id) &&
          (chat.blockedByPeer ||
              chat.peerIsGloballyBanned ||
              chat.peerIsDeleted ||
              (chat.avatarStoragePath == null &&
                  chat.avatarUrl == null &&
                  (old[chat.id]!.avatarStoragePath != null ||
                      old[chat.id]!.avatarUrl != null))),
    );
  }

  void _receivePresentation(ChatsState state) {
    final account = context.read<AccountSessionController?>();
    if (state.status == ChatsStatus.initial ||
        state.status == ChatsStatus.loading ||
        state.searchQuery != state.presentedQuery ||
        (account != null && account.userId == null)) {
      _presentationEpoch++;
      _preparingTarget = null;
      _preparingPaths = null;
      return;
    }
    final paths =
        _displayedState != null &&
            _displayedState!.searchQuery != state.presentedQuery &&
            !_hasAvatarRevocation(state)
        ? _incomingAvatarPaths(state)
        : <String>[];
    if (paths.isEmpty) {
      _presentationEpoch++;
      _preparingTarget = null;
      _preparingPaths = null;
      _commitPresentation(state);
      return;
    }
    if (_preparingTarget?.presentedQuery == state.presentedQuery &&
        _preparingPaths?.length == paths.length &&
        paths.indexed.every(
          (entry) => entry.$2 == _preparingPaths![entry.$1],
        )) {
      _preparingTarget = state;
      return;
    }
    final epoch = ++_presentationEpoch;
    _preparingTarget = state;
    _preparingPaths = paths;
    final session = account?.capture();
    bool current() =>
        mounted &&
        epoch == _presentationEpoch &&
        (session == null || account!.isCurrent(session));
    unawaited(
      LocalAvatarFrames.prepare(context, paths, isCurrent: current).then((
        lease,
      ) {
        if (!current()) {
          lease.dispose();
          return;
        }
        final target = _preparingTarget!;
        _preparingTarget = null;
        _preparingPaths = null;
        _heldFrames?.dispose();
        _heldFrames = lease;
        setState(() => _commitPresentation(target));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          lease.dispose();
          if (identical(_heldFrames, lease)) _heldFrames = null;
        });
      }),
    );
  }

  @override
  void dispose() {
    _presentationEpoch++;
    _heldFrames?.dispose();
    _rowMotion.dispose();
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
      if (_waitingFor(bloc.state)) return;
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
    if (_query != state.searchQuery) {
      if (_query.isEmpty && _scroll.hasClients) {
        _mainOffset = _scroll.offset;
        final height = MediaQuery.sizeOf(context).height;
        _mainAvatarIds = {
          for (final entry in _rows.entries)
            if (entry.value.findRenderObject() case final RenderBox box
                when box.attached &&
                    box.hasSize &&
                    box.localToGlobal(Offset.zero).dy + box.size.height > 130 &&
                    box.localToGlobal(Offset.zero).dy < height)
              entry.key,
        };
      }
      _query = state.searchQuery;
      final query = _query;
      final revision = ++_scrollQueryRevision;
      final destination = query.isEmpty ? _mainOffset : 0.0;
      _scroll.restoredOffset = destination;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            revision == _scrollQueryRevision &&
            _query == query &&
            _scroll.hasClients &&
            !_scroll.position.isScrollingNotifier.value) {
          final target = destination.clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          );
          if ((_scroll.offset - target).abs() > .5) {
            _scroll.jumpTo(target);
          }
        }
      });
      return;
    }
    if (!_scroll.hasClients) return;
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
    return BlocConsumer<ChatsBloc, ChatsState>(
      listener: (context, state) => _receivePresentation(state),
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.filteredChats != current.filteredChats ||
          previous.searchQuery != current.searchQuery ||
          previous.listQuery != current.listQuery ||
          previous.hasMoreChats != current.hasMoreChats ||
          previous.isLoadingMore != current.isLoadingMore ||
          previous.isRefreshing != current.isRefreshing ||
          previous.paginationError != current.paginationError ||
          previous.refreshError != current.refreshError ||
          previous.selectedChatIds != current.selectedChatIds ||
          previous.isSelectionMode != current.isSelectionMode,
      builder: (context, incoming) {
        if (_displayedState == null && !_waitingFor(incoming)) {
          _commitPresentation(incoming);
        }
        final state = _displayedState ?? incoming;
        final waiting = _waitingFor(incoming);
        _preserveAnchor(state);
        _scheduleViewport();
        final bottomPadding = widget.bottomPadding;
        Widget content() {
          switch (state.status) {
            case ChatsStatus.initial:
            case ChatsStatus.loading:
              return _ChatsFeedbackViewport(
                bottomPadding: bottomPadding,
                child: Center(
                  child: _ChatsLoadingIndicator(
                    key: ValueKey(state.searchQuery),
                  ),
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
                  if (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle &&
                      _motionActive &&
                      _scroll.hasClients) {
                    // Keep the remaining motion, but move its origin along
                    // with the user's drag instead of snapping it to the end.
                    _motionDragStart ??= _scroll.offset;
                  }
                  if (notification.depth == 0) _scheduleViewport();
                  return false;
                },
                child: ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indexes[key.value] : null,
                  padding: EdgeInsets.only(
                    top: 130,
                    bottom: widget.listBottomPadding,
                  ),
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
                      child: ChatListRowMotion(
                        progress: _rowMotion,
                        originY: _motionOrigins[chat.id],
                        entering: !_motionOrigins.containsKey(chat.id),
                        scrollDisplacement: _motionScrollDisplacement,
                        // During a paint-only move the old and new hit rectangles
                        // overlap. Block row taps briefly, but keep list scrolling.
                        child: IgnorePointer(
                          ignoring: _motionActive,
                          child: ChatListItem(
                            key: ValueKey(chat.id),
                            chat: chat,
                            avatarLoader: () => context
                                .read<IChatsRepository>()
                                .resolveAvatar(chat),
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
                                  context
                                      .read<ChatNavigationCoordinator>()
                                      .open(chat),
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
                        ),
                      ),
                    );
                  },
                ),
              );
          }
        }

        return NotificationListener<OverscrollIndicatorNotification>(
          onNotification: (notification) {
            // An edge drag also dismisses the search IME. Do not stretch the
            // whole list while its keyboard inset is changing: it creates a
            // small second rebound on top of the normal layout transition.
            if (notification.depth == 0 && widget.suppressEdgeStretch) {
              notification.disallowIndicator();
            }
            return false;
          },
          child: _ChatsPendingPresentation(
            pending: waiting && _displayedState != null,
            query: incoming.searchQuery,
            hasRows: state.filteredChats.isNotEmpty,
            bottomPadding: bottomPadding,
            child: AbsorbPointer(absorbing: waiting, child: content()),
          ),
        );
      },
    );
  }
}

/// A newly mounted list returns to the saved main offset on its first layout,
/// not after rendering the top page and applying a post-frame jump.
class _ChatsScrollController extends ScrollController {
  _ChatsScrollController() : super(keepScrollOffset: false);
  double restoredOffset = 0;
  @override
  double get initialScrollOffset => restoredOffset;
}

class _ChatsPendingPresentation extends StatefulWidget {
  const _ChatsPendingPresentation({
    required this.pending,
    required this.query,
    required this.hasRows,
    required this.bottomPadding,
    required this.child,
  });
  final bool pending, hasRows;
  final String query;
  final double bottomPadding;
  final Widget child;
  @override
  State<_ChatsPendingPresentation> createState() =>
      _ChatsPendingPresentationState();
}

class _ChatsPendingPresentationState extends State<_ChatsPendingPresentation> {
  Timer? _delay;
  bool _show = false;
  @override
  void initState() {
    super.initState();
    _updateDelay();
  }

  @override
  void didUpdateWidget(covariant _ChatsPendingPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pending != widget.pending ||
        oldWidget.query != widget.query) {
      _updateDelay();
    }
  }

  void _updateDelay() {
    _delay?.cancel();
    if (widget.pending && _show) return;
    _show = false;
    if (widget.pending) {
      _delay = Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _show = true);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox.square(
      dimension: 36,
      child: CircularProgressIndicator(strokeWidth: 4),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: _show && !widget.hasRows ? 0 : 1, child: widget.child),
        IgnorePointer(
          child: _ChatsFeedbackViewport(
            bottomPadding: widget.bottomPadding,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _show
                    ? const KeyedSubtree(
                        key: ValueKey('pending'),
                        child: spinner,
                      )
                    : const SizedBox.square(
                        key: ValueKey('idle'),
                        dimension: 36,
                      ),
              ),
            ),
          ),
        ),
      ],
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
