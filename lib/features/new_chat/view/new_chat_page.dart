import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/widgets.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  late final Stream<List<Friend>> _friendsStream;
  final _searchController = TextEditingController();
  final _openingFriendIds = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _friendsStream = context.read<IFriendsRepository>().watchFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddFriendPage() {
    FocusManager.instance.primaryFocus?.unfocus();
    final authRouter = context.router.root.innerRouterOf<StackRouter>(
      AuthGateRoute.name,
    );
    if (authRouter != null) {
      unawaited(authRouter.push(const AddFriendRoute()));
    }
  }

  Future<void> _openChat(Friend friend) async {
    if (!_openingFriendIds.add(friend.id)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final chat = await context.read<IChatsRepository>().prepareDirectChat(
        peerId: friend.id,
        peerUsername: friend.username,
        peerDisplayName: friend.displayName,
        peerAvatarUrl: friend.avatarUrl,
        peerAvatarStoragePath: friend.avatarStoragePath,
      );
      if (mounted) {
        await context.read<ChatNavigationCoordinator>().open(chat);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsChatOpenFailed,
          type: SnackBarType.error,
          bottomMargin: 84 + MediaQuery.paddingOf(context).bottom,
        );
      }
    } finally {
      _openingFriendIds.remove(friend.id);
    }
  }

  List<Friend> _filterFriends(List<Friend> friends) {
    final query = _query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (query.isEmpty) return friends;

    return friends
        .where((friend) {
          return friend.displayName.toLowerCase().contains(query) ||
              friend.username.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = keyboardInset > 0;
    final searchBottom = isKeyboardOpen
        ? keyboardInset + 16
        : mediaQuery.viewPadding.bottom + 16;
    final searchTop = mediaQuery.size.height - searchBottom - 50;
    final hideAppBar =
        mediaQuery.orientation == Orientation.landscape &&
        isKeyboardOpen &&
        searchTop < 130;
    const listTop = 146.0;
    final listBottom = searchBottom + 66;

    return KeyboardDismissPopScope(
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: hideAppBar
            ? null
            : PrimaryAppBar(title: context.l10n.newChatTitle),
        body: Stack(
          children: [
            StreamBuilder<List<Friend>>(
              stream: _friendsStream,
              builder: (context, snapshot) {
                final allFriends = snapshot.data ?? const <Friend>[];
                final friends = _filterFriends(allFriends);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: context.colorScheme.primary,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _StatusText(
                    message: context.l10n.friendsLoadFailed,
                    topPadding: 130,
                  );
                }
                if (allFriends.isEmpty) {
                  return _StaticNewChatContent(
                    showFindUser: true,
                    findUserTop: listTop,
                    onFindUser: _openAddFriendPage,
                    child: _StableEmptyFriendsState(
                      topPadding: 130,
                      bottomPadding: mediaQuery.viewPadding.bottom + 82,
                    ),
                  );
                }
                if (friends.isEmpty) {
                  return _StaticNewChatContent(
                    showFindUser: true,
                    findUserTop: listTop,
                    onFindUser: _openAddFriendPage,
                    child: _NoSearchResults(
                      topPadding: 130,
                      bottomPadding: mediaQuery.viewPadding.bottom + 82,
                    ),
                  );
                }

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(top: listTop, bottom: listBottom),
                  children: [
                    _FindUserRow(onPressed: _openAddFriendPage),
                    FriendsSectionTitle(
                      title: context.l10n.friendsAll,
                      count: friends.length,
                    ),
                    for (final friend in friends)
                      _NewChatFriendItem(
                        friend: friend,
                        avatarLoader: () => context
                            .read<IFriendsRepository>()
                            .resolveFriendAvatar(friend),
                        onTap: () => _openChat(friend),
                      ),
                  ],
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboardInset,
              child: const BottomAmbientGlow(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuad,
              left: 0,
              right: 0,
              bottom: searchBottom,
              child: GlassSearchBar(
                controller: _searchController,
                hintText: context.l10n.friendsSearchHint,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindUserRow extends StatelessWidget {
  const _FindUserRow({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16 + systemPadding.left,
        right: 16 + systemPadding.right,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.newChatFindUser,
              style: context.textTheme.headlineSmall?.copyWith(
                color: context.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          PrimaryIconButton(
            icon: Icons.person_add_alt_1_rounded,
            onTap: onPressed,
          ),
        ],
      ),
    );
  }
}

class _StaticNewChatContent extends StatelessWidget {
  const _StaticNewChatContent({
    required this.showFindUser,
    required this.findUserTop,
    required this.onFindUser,
    required this.child,
  });

  final bool showFindUser;
  final double findUserTop;
  final VoidCallback onFindUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (showFindUser)
          Positioned(
            top: findUserTop,
            left: 0,
            right: 0,
            child: _FindUserRow(onPressed: onFindUser),
          ),
      ],
    );
  }
}

class _NewChatFriendItem extends StatelessWidget {
  const _NewChatFriendItem({
    required this.friend,
    required this.avatarLoader,
    required this.onTap,
  });

  final Friend friend;
  final Future<String?> Function() avatarLoader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    final isOnline = context.select<PresenceCubit, bool>(
      (cubit) => cubit.state.isOnline(friend.id),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16 + systemPadding.left,
          right: 16 + systemPadding.right,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: friend.avatarUrl,
              avatarLoader: avatarLoader,
              avatarRevision: friend.avatarStoragePath ?? friend.avatarUrl,
              size: 54,
              borderRadius: 12,
              isOnline: isOnline,
              showOnlineBadge: true,
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
                    '@${friend.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.messagePreview.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StableEmptyFriendsState extends StatelessWidget {
  const _StableEmptyFriendsState({
    required this.topPadding,
    required this.bottomPadding,
  });

  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: EmptyChatState(message: context.l10n.friendsEmpty),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({
    required this.topPadding,
    required this.bottomPadding,
  });

  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: EmptyChatState(
        showImage: false,
        message: context.l10n.friendsNoSearchResults,
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.message, required this.topPadding});

  final String message;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + systemPadding.left,
        topPadding + 24,
        16 + systemPadding.right,
        16,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.textTheme.bodyLarge?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
