import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

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
  static const _cacheTtl = Duration(minutes: 10);
  static const _loadMoreThreshold = 280.0;
  static const _maxRequestsPerMinute = 8;

  final _scrollController = ScrollController();
  final _requestStarts = <DateTime>[];
  final _pendingActions = <String>{};

  late final Stream<List<Friend>> _friendsStream;
  late final Stream<List<FriendRequest>> _requestsStream;

  List<ViewedProfileFriend> _friends = const [];
  bool _hasSnapshot = false;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingFirstPage = false;
  bool _isLoadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final friendsRepository = context.read<IFriendsRepository>();
    _friendsStream = friendsRepository.watchCachedFriends();
    _requestsStream = friendsRepository.watchCachedRequests();
    _scrollController.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<IProfileRepository>();
    ViewedProfileFriendsSnapshot? snapshot;
    try {
      snapshot = await repository.getCachedViewedProfileFriendsSnapshot(
        widget.userId,
      );
    } catch (_) {
      // A damaged cache must not stop the remote page from being loaded.
    }
    if (!mounted) return;

    if (snapshot != null) {
      setState(() {
        _applySnapshot(snapshot!);
        _isLoading = false;
      });
      if (DateTime.now().toUtc().difference(snapshot.cachedAt) < _cacheTtl) {
        return;
      }
    }
    await _loadFirstPage();
  }

  bool _consumeRequestBudget() {
    final now = DateTime.now();
    _requestStarts.removeWhere(
      (startedAt) => now.difference(startedAt) >= const Duration(minutes: 1),
    );
    if (_requestStarts.length >= _maxRequestsPerMinute) return false;
    _requestStarts.add(now);
    return true;
  }

  Future<void> _loadFirstPage() async {
    if (_isLoadingFirstPage || _isLoadingMore || !_consumeRequestBudget()) {
      return;
    }
    setState(() {
      _isLoadingFirstPage = true;
      _isLoading = !_hasSnapshot;
      _failed = false;
    });
    try {
      final page = await context
          .read<IProfileRepository>()
          .refreshViewedProfileFriends(widget.userId);
      if (!mounted) return;
      setState(() {
        _friends = page.friends;
        _hasMore = page.hasMore;
        _hasSnapshot = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted && !_hasSnapshot) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingFirstPage = false;
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_isLoading ||
        _isLoadingFirstPage ||
        _isLoadingMore ||
        !_hasMore ||
        !_consumeRequestBudget()) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final snapshot = await context
          .read<IProfileRepository>()
          .loadMoreViewedProfileFriends(widget.userId);
      if (mounted && snapshot != null) {
        setState(() => _applySnapshot(snapshot));
      }
    } catch (_) {
      // Keep the previous page. The next scroll can safely retry.
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _applySnapshot(ViewedProfileFriendsSnapshot snapshot) {
    _friends = snapshot.friends;
    _hasMore = snapshot.hasMore;
    _hasSnapshot = true;
    _failed = false;
  }

  _FriendRelation _relationFor(
    List<Friend> friends,
    List<FriendRequest> requests,
    String friendId,
  ) {
    if (friends.any((friend) => friend.id == friendId)) {
      return const _FriendRelation(FriendRelationship.friend);
    }
    for (final request in requests) {
      if (request.peerId == friendId) {
        return _FriendRelation(
          request.direction == FriendRequestDirection.incoming
              ? FriendRelationship.incoming
              : FriendRelationship.outgoing,
          requestId: request.id,
        );
      }
    }
    return const _FriendRelation(FriendRelationship.none);
  }

  Future<void> _runFriendAction(
    ViewedProfileFriend friend,
    _FriendRelation relation, {
    required _FriendAction action,
  }) async {
    if (_pendingActions.contains(friend.id)) return;
    setState(() => _pendingActions.add(friend.id));
    final repository = context.read<IFriendsRepository>();
    try {
      switch (action) {
        case _FriendAction.add:
          await repository.sendRequest(
            FriendCandidate(
              id: friend.id,
              username: friend.username,
              displayName: friend.displayName,
              avatarUrl: friend.avatarUrl,
              avatarStoragePath: friend.avatarStoragePath,
              relationship: FriendRelationship.none,
            ),
          );
          return;
        case _FriendAction.cancel:
          final requestId = relation.requestId;
          if (requestId != null) await repository.cancelRequest(requestId);
          return;
        case _FriendAction.accept:
          final requestId = relation.requestId;
          if (requestId != null) {
            await repository.respondToRequest(requestId, accept: true);
          }
          return;
        case _FriendAction.reject:
          final requestId = relation.requestId;
          if (requestId != null) {
            await repository.respondToRequest(requestId, accept: false);
          }
          return;
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pendingActions.remove(friend.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(child: _buildContent(padding)),
          Positioned(
            top: padding.top + 16,
            left: padding.left + 16,
            right: padding.right + 16,
            child: Row(
              children: [
                GlassButton(
                  icon: Icons.arrow_back_rounded,
                  size: 50,
                  iconSize: 28,
                  borderRadius: 20,
                  onPressed: () => context.router.maybePop(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    context.l10n.viewedProfileUserFriends(widget.userName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(EdgeInsets padding) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: context.colorScheme.primary),
      );
    }
    if (_failed) return Center(child: Text(context.l10n.friendsLoadFailed));

    return StreamBuilder<List<Friend>>(
      stream: _friendsStream,
      builder: (context, friendsSnapshot) => StreamBuilder<List<FriendRequest>>(
        stream: _requestsStream,
        builder: (context, requestsSnapshot) => ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top + 92,
            padding.right,
            padding.bottom + 24,
          ),
          itemCount: _friends.isEmpty
              ? 1
              : _friends.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (_friends.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(child: Text(context.l10n.friendsEmpty)),
              );
            }
            if (index == _friends.length) {
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
            final friend = _friends[index];
            final relation = _relationFor(
              friendsSnapshot.data ?? const [],
              requestsSnapshot.data ?? const [],
              friend.id,
            );
            return _FriendRow(
              friend: friend,
              relation: relation,
              actionsAvailable:
                  friendsSnapshot.hasData && requestsSnapshot.hasData,
              isActionPending: _pendingActions.contains(friend.id),
              onAction: (action) =>
                  _runFriendAction(friend, relation, action: action),
              onTap: () =>
                  context.router.push(ViewedProfileRoute(userId: friend.id)),
            );
          },
        ),
      ),
    );
  }
}

enum _FriendAction { add, cancel, accept, reject }

class _FriendRelation {
  const _FriendRelation(this.relationship, {this.requestId});

  final FriendRelationship relationship;
  final String? requestId;
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.relation,
    required this.actionsAvailable,
    required this.isActionPending,
    required this.onAction,
    required this.onTap,
  });

  final ViewedProfileFriend friend;
  final _FriendRelation relation;
  final bool actionsAvailable;
  final bool isActionPending;
  final ValueChanged<_FriendAction> onAction;
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
            relation: relation,
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
    required this.relation,
    required this.enabled,
    required this.pending,
    required this.onAction,
  });

  final _FriendRelation relation;
  final bool enabled;
  final bool pending;
  final ValueChanged<_FriendAction> onAction;

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
    if (!enabled || relation.relationship == FriendRelationship.friend) {
      return const SizedBox(width: 64, height: 42);
    }
    return switch (relation.relationship) {
      FriendRelationship.none => PrimaryIconButton(
        icon: Icons.person_add_alt_1_rounded,
        onTap: () => onAction(_FriendAction.add),
      ),
      FriendRelationship.outgoing => GlassTextButton(
        label: context.l10n.friendsCancelRequest,
        onTap: () => onAction(_FriendAction.cancel),
      ),
      FriendRelationship.incoming => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryIconButton(
            icon: Icons.check_rounded,
            width: 54,
            onTap: () => onAction(_FriendAction.accept),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            height: 42,
            child: IconButton(
              onPressed: () => onAction(_FriendAction.reject),
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
