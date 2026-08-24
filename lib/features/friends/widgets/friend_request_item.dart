import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class FriendRequestItem extends StatelessWidget {
  const FriendRequestItem({
    super.key,
    required this.request,
    required this.cancelLabel,
    required this.friendsLabel,
    required this.onCancel,
    required this.onAccept,
    required this.onReject,
    this.onTap,
  });

  final FriendRequest request;
  final String cancelLabel;
  final String Function(int count) friendsLabel;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
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
              avatarUrl: request.peerAvatarUrl,
              size: 54,
              borderRadius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.peerDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.chatName.copyWith(
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    request.peerFriendCount == null
                        ? '@${request.peerUsername}'
                        : friendsLabel(request.peerFriendCount!),
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
            if (request.direction == FriendRequestDirection.outgoing)
              GlassTextButton(label: cancelLabel, onTap: onCancel)
            else ...[
              PrimaryIconButton(
                icon: Icons.check_rounded,
                onTap: onAccept,
                width: 54,
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Icons.close_rounded,
                onTap: onReject,
                width: 46,
                height: 42,
                borderRadius: 21,
                iconSize: 26,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
