import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/bloc/bloc.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class UserFriendsPage extends StatefulWidget {
  const UserFriendsPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  State<UserFriendsPage> createState() => _UserFriendsPageState();
}

class _UserFriendsPageState extends State<UserFriendsPage> {
  static const _loadMoreThreshold = 280.0;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  late final UserFriendsCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = UserFriendsCubit(
      userId: widget.userId,
      profileRepository: context.read<IProfileRepository>(),
      friendsRepository: context.read<IFriendsRepository>(),
    );
    _scrollController.addListener(_onScroll);
    unawaited(_cubit.initialize());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    unawaited(_cubit.loadMore());
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _cubit,
    child: BlocListener<UserFriendsCubit, UserFriendsState>(
      listenWhen: (previous, current) =>
          previous.actionErrorId != current.actionErrorId,
      listener: (context, state) => showAppSnackBar(
        context,
        message: context.l10n.friendsActionFailed,
        type: SnackBarType.error,
      ),
      child: BlocBuilder<UserFriendsCubit, UserFriendsState>(
        builder: (context, state) => _UserFriendsContent(
          scrollController: _scrollController,
          searchController: _searchController,
          state: state,
          onSearchChanged: _cubit.searchChanged,
          onAction: _cubit.performAction,
        ),
      ),
    ),
  );
}

class _UserFriendsContent extends StatelessWidget {
  const _UserFriendsContent({
    required this.scrollController,
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onAction,
  });

  final ScrollController scrollController;
  final TextEditingController searchController;
  final UserFriendsState state;
  final ValueChanged<String> onSearchChanged;
  final void Function(ViewedProfileFriend, UserFriendsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    const searchBarSpacing = 16.0;
    const searchBarHeight = 50.0;
    final searchBarBottomOffset = keyboardHeight > 0
        ? keyboardHeight + searchBarSpacing
        : mediaQuery.viewPadding.bottom + searchBarSpacing;
    final contentBottomPadding =
        searchBarBottomOffset + searchBarHeight + searchBarSpacing;
    final titleStyle = AppTextStyles.titleLargeFlex.copyWith(
      color: context.colorScheme.onSurface,
      fontSize: 44,
    );
    final countStyle = titleStyle.copyWith(
      color: context.colorScheme.onSurfaceVariant,
      fontVariations: const [
        FontVariation('wght', 900),
        FontVariation('GRAD', 150),
        FontVariation('XOPQ', 106),
        FontVariation('YTLC', 518),
        FontVariation('slnt', 0),
      ],
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildContent(
              context,
              padding,
              bottomPadding: contentBottomPadding,
            ),
          ),
          AnimatedPositioned(
            duration: Duration.zero,
            left: 0,
            right: 0,
            bottom: keyboardHeight > 0 ? keyboardHeight : 0,
            child: const BottomAmbientGlow(),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutQuad,
            left: 0,
            right: 0,
            bottom: searchBarBottomOffset,
            child: GlassSearchBar(
              controller: searchController,
              hintText: context.l10n.friendsSearchHint,
              onChanged: onSearchChanged,
            ),
          ),
          Positioned(
            top: padding.top + 16,
            left: padding.left + 16,
            right: padding.right + 16,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: context.l10n.viewedProfileFriendsTitle),
                  TextSpan(
                    text: ' ${state.totalFriendCount}',
                    style: countStyle,
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    EdgeInsets padding, {
    required double bottomPadding,
  }) {
    if (state.status == UserFriendsStatus.initial ||
        state.status == UserFriendsStatus.loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colorScheme.primary),
      );
    }
    if (state.status == UserFriendsStatus.failure) {
      return _FriendsEmptyState(
        message: context.l10n.friendsLoadFailed,
        topPadding: padding.top + 156,
      );
    }

    final visibleFriends = state.visibleFriends;
    if (visibleFriends.isEmpty) {
      return _FriendsEmptyState(
        message: state.isSearching
            ? context.l10n.friendsNoSearchResults
            : context.l10n.friendsEmpty,
        topPadding: padding.top + 156,
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        padding.left,
        padding.top + 92,
        padding.right,
        bottomPadding,
      ),
      itemCount:
          visibleFriends.length +
          (state.isLoadingMore && !state.isSearching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visibleFriends.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        final friend = visibleFriends[index];
        final relationship = state.relationFor(friend.id).relationship;
        return _FriendRow(
          friend: friend,
          relationship: relationship,
          actionsAvailable: state.hasRelationshipSnapshot,
          isActionPending: state.isActionPending(friend.id),
          onAction: (action) => onAction(friend, action),
          onTap: () =>
              context.router.push(ViewedProfileRoute(userId: friend.id)),
        );
      },
    );
  }
}

class _FriendsEmptyState extends StatelessWidget {
  const _FriendsEmptyState({required this.message, required this.topPadding});

  final String message;
  final double topPadding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.only(top: topPadding, left: 24, right: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.colorScheme.onSurfaceVariant,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    ),
  );
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.relationship,
    required this.actionsAvailable,
    required this.isActionPending,
    required this.onAction,
    required this.onTap,
  });

  final ViewedProfileFriend friend;
  final FriendRelationship relationship;
  final bool actionsAvailable;
  final bool isActionPending;
  final ValueChanged<UserFriendsAction> onAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ProfileAvatarHero(
            profileId: friend.id,
            avatarUrl: friend.avatarUrl,
            avatarStoragePath: friend.avatarStoragePath,
            child: UserAvatar(
              avatarUrl: friend.avatarUrl,
              avatarLoader: () => context
                  .read<IProfileRepository>()
                  .resolveViewedProfileFriendAvatar(friend),
              preferAvatarLoader: true,
              avatarRevision: friend.avatarStoragePath ?? friend.avatarUrl,
              size: 54,
              borderRadius: 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.chatName.copyWith(
                    color: context.colorScheme.onSurface,
                  ),
                ),
                Text(
                  context.l10n.viewedProfileMutualFriends(
                    friend.mutualFriendCount,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.messagePreview.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _FriendActions(
            relationship: relationship,
            enabled: actionsAvailable && !isActionPending,
            pending: isActionPending,
            onAction: onAction,
          ),
        ],
      ),
    ),
  );
}

class _FriendActions extends StatelessWidget {
  const _FriendActions({
    required this.relationship,
    required this.enabled,
    required this.pending,
    required this.onAction,
  });

  final FriendRelationship relationship;
  final bool enabled;
  final bool pending;
  final ValueChanged<UserFriendsAction> onAction;

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return SizedBox(
        width: 64,
        height: 42,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: context.colorScheme.primary,
            ),
          ),
        ),
      );
    }
    if (!enabled || relationship == FriendRelationship.friend) {
      return const SizedBox(width: 64, height: 42);
    }
    return switch (relationship) {
      FriendRelationship.none => PrimaryIconButton(
        icon: Icons.person_add_alt_1_rounded,
        onTap: () => onAction(UserFriendsAction.add),
      ),
      FriendRelationship.outgoing => GlassTextButton(
        label: context.l10n.friendsCancelRequest,
        onTap: () => onAction(UserFriendsAction.cancel),
      ),
      FriendRelationship.incoming => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryIconButton(
            icon: Icons.check_rounded,
            width: 54,
            onTap: () => onAction(UserFriendsAction.accept),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            height: 42,
            child: IconButton(
              onPressed: () => onAction(UserFriendsAction.reject),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              iconSize: 26,
              color: context.colorScheme.onSurface,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
      FriendRelationship.friend => const SizedBox(width: 64, height: 42),
    };
  }
}
