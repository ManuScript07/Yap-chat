import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/friend_request_reject_button.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/ui/ui.dart';

class ContactDiscoveryItem extends StatelessWidget {
  const ContactDiscoveryItem({
    super.key,
    required this.entry,
    required this.friendsLabel,
    required this.notRegisteredLabel,
    required this.checkingLabel,
    required this.unknownLabel,
    required this.isRefreshing,
    required this.hiddenFriendCountLabel,
    required this.inviteLabel,
    required this.relationshipLabel,
    required this.onAdd,
    required this.onInvite,
    required this.onAccept,
    required this.onReject,
    this.avatarLoader,
    this.onTap,
  });

  final ContactDiscoveryEntry entry;
  final String Function(int count) friendsLabel;
  final String notRegisteredLabel;
  final String checkingLabel;
  final String unknownLabel;
  final bool isRefreshing;
  final String hiddenFriendCountLabel;
  final String inviteLabel;
  final String Function(FriendRelationship relationship) relationshipLabel;
  final VoidCallback onAdd;
  final VoidCallback onInvite;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final Future<String?> Function()? avatarLoader;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final candidate = entry.candidate;
    return InkWell(
      onTap: candidate == null ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (candidate == null)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: context.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: context.colorScheme.onPrimary,
                  size: 30,
                ),
              )
            else
              ProfileAvatarHero(
                profileId: candidate.id,
                avatarUrl: candidate.avatarUrl,
                avatarStoragePath: candidate.avatarStoragePath,
                child: UserAvatar(
                  avatarUrl: candidate.avatarUrl,
                  avatarLoader: avatarLoader,
                  avatarRevision:
                      candidate.avatarStoragePath ?? candidate.avatarUrl,
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
                    candidate?.displayName ?? entry.contact.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.chatName.copyWith(
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    candidate == null
                        ? switch (entry.matchStatus) {
                            ContactMatchStatus.notRegistered =>
                              notRegisteredLabel,
                            ContactMatchStatus.unknown =>
                              isRefreshing ? checkingLabel : unknownLabel,
                            ContactMatchStatus.matched => unknownLabel,
                          }
                        : candidate.friendCount == null
                        ? hiddenFriendCountLabel
                        : friendsLabel(candidate.friendCount!),
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
            if (entry.matchStatus == ContactMatchStatus.notRegistered)
              GlassTextButton(
                label: inviteLabel,
                onTap: onInvite,
                horizontalPadding: 15,
                backgroundColor: context.colorScheme.onSurface.withValues(
                  alpha: 0.14,
                ),
                foregroundColor: context.colorScheme.onSurface,
              )
            else if (candidate != null)
              _CandidateAction(
                candidate: candidate,
                relationshipLabel: relationshipLabel,
                onAdd: onAdd,
                onAccept: onAccept,
                onReject: onReject,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _CandidateAction extends StatelessWidget {
  const _CandidateAction({
    required this.candidate,
    required this.relationshipLabel,
    required this.onAdd,
    required this.onAccept,
    required this.onReject,
  });

  final FriendCandidate candidate;
  final String Function(FriendRelationship relationship) relationshipLabel;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return switch (candidate.relationship) {
      FriendRelationship.none => PrimaryIconButton(
        icon: Icons.person_add_alt_1_rounded,
        onTap: onAdd,
      ),
      FriendRelationship.incoming => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryIconButton(
            icon: Icons.check_rounded,
            onTap: onAccept,
            width: 54,
          ),
          const SizedBox(width: 8),
          FriendRequestRejectButton(onTap: onReject),
        ],
      ),
      FriendRelationship.outgoing => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 92),
        child: Text(
          relationshipLabel(candidate.relationship),
          textAlign: TextAlign.end,
          style: context.textTheme.labelLarge?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      FriendRelationship.friend => const SizedBox.shrink(),
    };
  }
}
