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
    final systemPadding = MediaQuery.paddingOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      appBar: PrimaryAppBar(title: context.l10n.newChatTitle),
      body: Stack(
        children: [
          StreamBuilder<List<Friend>>(
            stream: _friendsStream,
            builder: (context, snapshot) {
              final friends = _filterFriends(snapshot.data ?? const []);
              return ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  top: 16,
                  bottom: systemPadding.bottom + 98,
                ),
                children: [
                  _FindUserRow(onPressed: _openAddFriendPage),
                  FriendsSectionTitle(
                    title: context.l10n.friendsAll,
                    count: friends.length,
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: context.colorScheme.primary,
                        ),
                      ),
                    )
                  else if (snapshot.hasError)
                    _StatusText(message: context.l10n.friendsLoadFailed)
                  else if (friends.isEmpty)
                    _StatusText(
                      message: _query.trim().isEmpty
                          ? context.l10n.friendsEmpty
                          : context.l10n.friendsNoSearchResults,
                    )
                  else
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
          Positioned(
            left: 0,
            right: 0,
            bottom:
                16 + (keyboardInset > 0 ? keyboardInset : systemPadding.bottom),
            child: GlassSearchBar(
              controller: _searchController,
              hintText: context.l10n.friendsSearchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ],
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

class _StatusText extends StatelessWidget {
  const _StatusText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + systemPadding.left,
        24,
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
