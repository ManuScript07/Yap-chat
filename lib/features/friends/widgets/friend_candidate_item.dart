import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/friend_request_reject_button.dart';
import 'package:yap_chat/ui/ui.dart';

class FriendCandidateItem extends StatelessWidget {
  const FriendCandidateItem({
    super.key,
    required this.candidate,
    required this.friendsLabel,
    required this.onAdd,
    required this.relationshipLabel,
    required this.onAccept,
    required this.onReject,
    this.avatarLoader,
    this.respectSystemPadding = true,
  });

  final FriendCandidate candidate;
  final String Function(int count) friendsLabel;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final String Function(FriendRelationship relationship) relationshipLabel;
  final Future<String?> Function()? avatarLoader;
  final bool respectSystemPadding;

  @override
  Widget build(BuildContext context) {
    final systemPadding = respectSystemPadding
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    final canAdd = candidate.relationship == FriendRelationship.none;
    return Padding(
      padding: EdgeInsets.only(
        left: 16 + systemPadding.left,
        right: 16 + systemPadding.right,
        top: 10,
        bottom: 10,
      ),
      child: Row(
        children: [
          UserAvatar(
            avatarUrl: candidate.avatarUrl,
            avatarLoader: avatarLoader,
            avatarRevision: candidate.avatarStoragePath ?? candidate.avatarUrl,
            size: 54,
            borderRadius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.chatName.copyWith(
                    color: context.colorScheme.onSurface,
                  ),
                ),
                Text(
                  candidate.friendCount == null
                      ? '@${candidate.username}'
                      : '${friendsLabel(candidate.friendCount!)} · @${candidate.username}',
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
          if (canAdd)
            PrimaryIconButton(
              icon: Icons.person_add_alt_1_rounded,
              onTap: onAdd,
            )
          else if (candidate.relationship == FriendRelationship.incoming) ...[
            PrimaryIconButton(
              icon: Icons.check_rounded,
              onTap: onAccept,
              width: 54,
            ),
            const SizedBox(width: 8),
            FriendRequestRejectButton(onTap: onReject),
          ] else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 108),
              child: Text(
                relationshipLabel(candidate.relationship),
                textAlign: TextAlign.end,
                style: context.textTheme.labelLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
