import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
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
  List<ViewedProfileFriend> _friends = const [];
  bool _isLoading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = context.read<IProfileRepository>();
    final cached = await repository.getCachedViewedProfileFriends(
      widget.userId,
    );
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _friends = cached;
        _isLoading = false;
      });
    }
    try {
      final remote = await repository.getViewedProfileFriends(widget.userId);
      if (mounted) {
        setState(() {
          _friends = remote;
          _isLoading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = cached.isEmpty;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: context.colorScheme.primary,
                    ),
                  )
                : _failed
                ? Center(child: Text(context.l10n.friendsLoadFailed))
                : _friends.isEmpty
                ? Center(child: Text(context.l10n.friendsEmpty))
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      padding.top + 92,
                      padding.right,
                      padding.bottom + 24,
                    ),
                    itemCount: _friends.length,
                    itemBuilder: (context, index) => _FriendRow(
                      friend: _friends[index],
                      onTap: () => context.router.push(
                        ViewedProfileRoute(userId: _friends[index].id),
                      ),
                    ),
                  ),
          ),
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
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.onTap});

  final ViewedProfileFriend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ProfileAvatarHero(
            avatarUrl: friend.avatarUrl,
            avatarStoragePath: friend.avatarStoragePath,
            child: UserAvatar(
              avatarUrl: friend.avatarUrl,
              avatarLoader: () => context
                  .read<IProfileRepository>()
                  .resolveViewedProfileFriendAvatar(friend),
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
                  style: TextStyle(
                    color: context.colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '@${friend.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );
}
