import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/ui/ui.dart';

class FriendListItem extends StatelessWidget {
  const FriendListItem({
    super.key,
    required this.friend,
    required this.onChat,
    required this.onLocation,
    this.onTap,
    this.avatarLoader,
  });

  final Friend friend;
  final VoidCallback onChat;
  final VoidCallback onLocation;
  final VoidCallback? onTap;
  final Future<String?> Function()? avatarLoader;

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
            const SizedBox(width: 8),
            PrimaryIconButton(icon: Icons.chat_rounded, onTap: onChat),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.near_me_rounded,
              onTap: onLocation,
              width: 46,
              height: 42,
              borderRadius: 21,
              iconSize: 25,
            ),
          ],
        ),
      ),
    );
  }
}
