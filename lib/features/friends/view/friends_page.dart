import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FriendSearchCubit(repository: context.read<IFriendsRepository>()),
      child: const _FriendsPageView(),
    );
  }
}

bool _isGlobalFriendQuery(String query) {
  if (query.startsWith('@')) return query.substring(1).length >= 3;
  return query.length >= 3;
}

class _FriendsPageView extends StatelessWidget {
  const _FriendsPageView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FriendsBloc, FriendsState>(
      buildWhen: (previous, current) =>
          previous.activeTab != current.activeTab ||
          previous.incomingRequestCount != current.incomingRequestCount,
      builder: (context, state) {
        final mediaQuery = MediaQuery.of(context);
        final isLandscapeKeyboard =
            mediaQuery.orientation == Orientation.landscape &&
            mediaQuery.viewInsets.bottom > 0;
        const appBarHeight = 130.0;
        const searchBarHeight = 50.0;
        const searchBarSpacing = 16.0;
        final searchBarTop =
            mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            searchBarSpacing -
            searchBarHeight;
        final hideAppBar = isLandscapeKeyboard && searchBarTop < appBarHeight;

        return ScaffoldMessenger(
          child: Builder(
            builder: (scaffoldContext) =>
                BlocListener<FriendsBloc, FriendsState>(
                  listenWhen: (previous, current) =>
                      previous.actionError != current.actionError &&
                      current.actionError != null,
                  listener: (context, state) {
                    showAppSnackBar(
                      scaffoldContext,
                      message: context.l10n.friendsActionFailed,
                      type: SnackBarType.error,
                      bottomMargin: 156,
                    );
                    context.read<FriendsBloc>().add(
                      const FriendsActionFailureCleared(),
                    );
                  },
                  child: BlocListener<FriendSearchCubit, FriendSearchState>(
                    listenWhen: (previous, current) =>
                        previous.actionError != current.actionError &&
                        current.actionError != null,
                    listener: (context, state) {
                      showAppSnackBar(
                        scaffoldContext,
                        message: context.l10n.friendsActionFailed,
                        type: SnackBarType.error,
                        bottomMargin: 156,
                      );
                      context.read<FriendSearchCubit>().clearActionError();
                    },
                    child: Scaffold(
                      resizeToAvoidBottomInset: false,
                      extendBodyBehindAppBar: true,
                      backgroundColor: context.scaffoldBackgroundColor,
                      appBar: hideAppBar
                          ? null
                          : PrimaryAppBar(
                              title: context.l10n.navFriends,
                              titleWidget:
                                  mediaQuery.orientation ==
                                      Orientation.landscape
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _FriendsTabs(
                                        state: state,
                                        horizontalPadding: 0,
                                      ),
                                    )
                                  : null,
                              actionIcon: Icons.person_add_alt_1_rounded,
                              onActionPressed: () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                final authRouter = context.router.root
                                    .innerRouterOf<StackRouter>(
                                      AuthGateRoute.name,
                                    );
                                if (authRouter != null) {
                                  unawaited(
                                    authRouter.push(const AddFriendRoute()),
                                  );
                                }
                              },
                            ),
                      body: _FriendsBody(
                        isLandscape:
                            mediaQuery.orientation == Orientation.landscape,
                        contentTop: hideAppBar ? 0 : appBarHeight,
                      ),
                    ),
                  ),
                ),
          ),
        );
      },
    );
  }
}

class _FriendsBody extends StatefulWidget {
  const _FriendsBody({required this.isLandscape, required this.contentTop});

  final bool isLandscape;
  final double contentTop;

  @override
  State<_FriendsBody> createState() => _FriendsBodyState();
}

class _FriendsBodyState extends State<_FriendsBody> {
  final _friendsSearchController = TextEditingController();
  final _requestsSearchController = TextEditingController();

  @override
  void dispose() {
    _friendsSearchController.dispose();
    _requestsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;
    const navBarHeight = 70.0;
    const navBarBottomOffset = 16.0;
    const searchBarSpacing = 16.0;
    const searchBarHeight = 50.0;
    const contentExtraPadding = 16.0;
    final navigationSpace =
        mediaQuery.viewPadding.bottom + navBarBottomOffset + navBarHeight;
    final searchBarBottomOffset = isKeyboardOpen
        ? keyboardHeight + searchBarSpacing
        : navigationSpace + searchBarSpacing;
    final contentBottomPadding =
        searchBarBottomOffset + searchBarHeight + contentExtraPadding;
    final glowBottomOffset = isKeyboardOpen ? keyboardHeight : 0.0;
    final listTopPadding = widget.isLandscape && widget.contentTop > 0
        ? 104.0
        : widget.contentTop;

    return BlocBuilder<FriendsBloc, FriendsState>(
      builder: (context, state) {
        final activeIndex = state.activeTab.index;
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            if (widget.isLandscape) ...[
              Positioned.fill(
                child: IndexedStack(
                  index: activeIndex,
                  children: [
                    _FriendsList(
                      isLandscape: widget.isLandscape,
                      topPadding: listTopPadding,
                      bottomPadding: contentBottomPadding,
                    ),
                    _RequestsList(
                      isLandscape: widget.isLandscape,
                      topPadding: listTopPadding,
                      bottomPadding: contentBottomPadding,
                    ),
                  ],
                ),
              ),
              GradientOverlay(
                height: listTopPadding + (widget.contentTop == 0 ? 90 : 20),
                isTop: true,
                backgroundColor: context.scaffoldBackgroundColor,
              ),
              if (widget.contentTop == 0)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: _FriendsTabs(state: state),
                ),
            ] else
              Positioned.fill(
                top: widget.contentTop,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _FriendsTabs(state: state),
                    const SizedBox(height: 4),
                    Expanded(
                      child: IndexedStack(
                        index: activeIndex,
                        children: [
                          _FriendsList(bottomPadding: contentBottomPadding),
                          _RequestsList(bottomPadding: contentBottomPadding),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedPositioned(
              duration: Duration.zero,
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
              bottom: searchBarBottomOffset,
              child: GlassSearchBar(
                key: ValueKey(state.activeTab),
                controller: state.activeTab == FriendsTab.friends
                    ? _friendsSearchController
                    : _requestsSearchController,
                hintText: context.l10n.friendsSearchHint,
                onChanged: (value) {
                  context.read<FriendsBloc>().add(FriendsSearchChanged(value));
                  if (state.activeTab == FriendsTab.friends) {
                    context.read<FriendSearchCubit>().queryChanged(value);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FriendsTabs extends StatelessWidget {
  const _FriendsTabs({required this.state, this.horizontalPadding = 16});

  final FriendsState state;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return PrimarySegmentedControl(
      horizontalPadding: horizontalPadding,
      items: [
        PrimarySegmentItem(label: context.l10n.friendsTabFriends),
        PrimarySegmentItem(
          label: context.l10n.friendsTabRequests,
          count: state.incomingRequestCount,
        ),
      ],
      selectedIndex: state.activeTab.index,
      onChanged: (index) {
        FocusManager.instance.primaryFocus?.unfocus();
        context.read<FriendsBloc>().add(
          FriendsTabChanged(FriendsTab.values[index]),
        );
      },
    );
  }
}

class _FriendsList extends StatefulWidget {
  const _FriendsList({
    required this.bottomPadding,
    this.topPadding = 0,
    this.isLandscape = false,
  });

  final double topPadding;
  final double bottomPadding;
  final bool isLandscape;

  @override
  State<_FriendsList> createState() => _FriendsListState();
}

class _FriendsListState extends State<_FriendsList> {
  static const _locationLaunchCooldown = Duration(seconds: 2);
  final _openingLocations = <String>{};

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FriendsBloc, FriendsState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.friends != current.friends ||
          previous.friendsQuery != current.friendsQuery,
      builder: (context, state) =>
          BlocBuilder<FriendSearchCubit, FriendSearchState>(
            builder: (context, searchState) {
              if (state.status == FriendsStatus.initial ||
                  state.status == FriendsStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status == FriendsStatus.failure) {
                return Center(child: Text(context.l10n.friendsLoadFailed));
              }
              final friends = state.filteredFriends;
              final query = state.friendsQuery.trim();
              final showGlobal = _isGlobalFriendQuery(query);
              if (friends.isEmpty && !showGlobal) {
                final emptyState = EmptyChatState(
                  showImage: query.isEmpty,
                  message: query.isEmpty
                      ? context.l10n.friendsEmpty
                      : context.l10n.friendsNoSearchResults,
                );
                if (widget.isLandscape) {
                  return ListView(
                    key: const PageStorageKey('friends-empty-state'),
                    padding: EdgeInsets.only(
                      top: widget.topPadding,
                      bottom: widget.bottomPadding,
                    ),
                    children: [emptyState],
                  );
                }
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutQuad,
                  padding: EdgeInsets.only(
                    top: widget.topPadding,
                    bottom: widget.bottomPadding,
                  ),
                  child: emptyState,
                );
              }
              return ListView(
                key: const PageStorageKey('friends-list'),
                padding: EdgeInsets.only(
                  top: widget.topPadding,
                  bottom: widget.bottomPadding,
                ),
                children: [
                  if (friends.isNotEmpty) ...[
                    FriendsSectionTitle(
                      title: query.isEmpty
                          ? context.l10n.friendsAll
                          : context.l10n.friendsTabFriends,
                      count: friends.length,
                    ),
                    ...friends.map(
                      (friend) => FriendListItem(
                        key: ValueKey(friend.id),
                        friend: friend,
                        avatarLoader: () => context
                            .read<IFriendsRepository>()
                            .resolveFriendAvatar(friend),
                        onChat: () => _openChat(context, friend),
                        onLocation: () => _openLocation(context, friend),
                        isLocationEnabled: !_openingLocations.contains(
                          friend.id,
                        ),
                      ),
                    ),
                  ],
                  if (showGlobal) ...[
                    FriendsSectionTitle(
                      title: context.l10n.friendsGlobalSearch,
                    ),
                    ..._globalSearchChildren(context, searchState),
                  ],
                ],
              );
            },
          ),
    );
  }

  List<Widget> _globalSearchChildren(
    BuildContext context,
    FriendSearchState state,
  ) {
    final widgets = <Widget>[];
    if (state.status == FriendSearchStatus.loading) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      );
    }
    if (state.status == FriendSearchStatus.failure) {
      widgets.add(
        _globalMessage(context, context.l10n.friendsUserSearchFailed),
      );
      return widgets;
    }
    if (state.status == FriendSearchStatus.success && state.results.isEmpty) {
      widgets.add(
        SizedBox(
          height: 150,
          child: EmptyChatState(
            showImage: false,
            message: context.l10n.friendsNoSearchResults,
          ),
        ),
      );
      return widgets;
    }
    final repository = context.read<IFriendsRepository>();
    final cubit = context.read<FriendSearchCubit>();
    widgets.addAll(
      state.results.map(
        (candidate) => FriendCandidateItem(
          key: ValueKey('global:${candidate.id}'),
          candidate: candidate,
          friendsLabel: context.l10n.friendsCount,
          relationshipLabel: (relationship) => switch (relationship) {
            FriendRelationship.friend => context.l10n.friendsAlreadyAdded,
            FriendRelationship.outgoing => context.l10n.friendsRequestSent,
            FriendRelationship.incoming => context.l10n.friendsRequestIncoming,
            FriendRelationship.none => '',
          },
          avatarLoader: () => repository.resolveCandidateAvatar(candidate),
          onAdd: () => cubit.sendRequest(candidate),
          onAccept: () => cubit.respondToIncoming(candidate, accept: true),
          onReject: () => cubit.respondToIncoming(candidate, accept: false),
        ),
      ),
    );
    return widgets;
  }

  Widget _globalMessage(BuildContext context, String message) {
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + systemPadding.left,
        12,
        16 + systemPadding.right,
        20,
      ),
      child: Text(
        message,
        style: context.textTheme.bodyLarge?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _openChat(BuildContext context, Friend friend) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final chat = await context.read<IChatsRepository>().prepareDirectChat(
        peerId: friend.id,
        peerUsername: friend.username,
        peerDisplayName: friend.displayName,
        peerAvatarUrl: friend.avatarUrl,
        peerAvatarStoragePath: friend.avatarStoragePath,
      );
      if (context.mounted) {
        await context.read<ChatNavigationCoordinator>().open(chat);
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsChatOpenFailed,
          type: SnackBarType.error,
          bottomMargin: 156,
        );
      }
    }
  }

  Future<void> _openLocation(BuildContext context, Friend friend) async {
    if (!_openingLocations.add(friend.id)) return;
    final startedAt = DateTime.now();
    if (mounted) setState(() {});
    try {
      final location = await context
          .read<IFriendsRepository>()
          .getFriendLocation(friend.id);
      if (!context.mounted) return;
      if (location == null) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsLocationUnavailable,
          bottomMargin: 156,
        );
        return;
      }
      final uri = Uri.parse(
        'geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}',
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !context.mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.locationOpenError,
        type: SnackBarType.error,
        bottomMargin: 156,
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.locationOpenError,
          type: SnackBarType.error,
          bottomMargin: 156,
        );
      }
    } finally {
      final elapsed = DateTime.now().difference(startedAt);
      final cooldownLeft = _locationLaunchCooldown - elapsed;
      if (cooldownLeft > Duration.zero) {
        await Future<void>.delayed(cooldownLeft);
      }
      _openingLocations.remove(friend.id);
      if (mounted) setState(() {});
    }
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.bottomPadding,
    this.topPadding = 0,
    this.isLandscape = false,
  });

  final double topPadding;
  final double bottomPadding;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FriendsBloc, FriendsState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.requests != current.requests ||
          previous.requestsQuery != current.requestsQuery,
      builder: (context, state) {
        if (state.status == FriendsStatus.initial ||
            state.status == FriendsStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == FriendsStatus.failure) {
          return Center(child: Text(context.l10n.friendsLoadFailed));
        }
        final incoming = state.incomingRequests;
        final outgoing = state.outgoingRequests;
        if (incoming.isEmpty && outgoing.isEmpty) {
          final emptyState = EmptyChatState(
            showImage: state.requestsQuery.trim().isEmpty,
            message: state.requestsQuery.trim().isEmpty
                ? context.l10n.friendsRequestsEmpty
                : context.l10n.friendsNoSearchResults,
          );
          if (isLandscape) {
            return ListView(
              key: const PageStorageKey('friend-requests-empty-state'),
              padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
              children: [emptyState],
            );
          }
          return AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutQuad,
            padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
            child: emptyState,
          );
        }
        return ListView(
          key: const PageStorageKey('friend-requests-list'),
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          children: [
            if (outgoing.isNotEmpty) ...[
              FriendsSectionTitle(
                title: context.l10n.friendsOutgoing,
                count: outgoing.length,
              ),
              ...outgoing.map((request) => _item(context, request)),
            ],
            if (incoming.isNotEmpty) ...[
              FriendsSectionTitle(
                title: context.l10n.friendsIncoming,
                count: incoming.length,
              ),
              ...incoming.map((request) => _item(context, request)),
            ],
          ],
        );
      },
    );
  }

  Widget _item(BuildContext context, FriendRequest request) {
    return FriendRequestItem(
      key: ValueKey(request.id),
      request: request,
      avatarLoader: () =>
          context.read<IFriendsRepository>().resolveRequestAvatar(request),
      cancelLabel: context.l10n.friendsCancelRequest,
      friendsLabel: context.l10n.friendsCount,
      onCancel: () =>
          context.read<FriendsBloc>().add(FriendRequestCancelled(request.id)),
      onAccept: () => context.read<FriendsBloc>().add(
        FriendRequestResponded(request.id, accept: true),
      ),
      onReject: () => context.read<FriendsBloc>().add(
        FriendRequestResponded(request.id, accept: false),
      ),
    );
  }
}
