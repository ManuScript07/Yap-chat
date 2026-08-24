import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class ContactDiscoveryItem extends StatelessWidget {
  const ContactDiscoveryItem({
    super.key,
    required this.entry,
    required this.friendsLabel,
    required this.notRegisteredLabel,
    required this.hiddenFriendCountLabel,
    required this.inviteLabel,
    required this.relationshipLabel,
    required this.onAdd,
    required this.onInvite,
    required this.onAccept,
    required this.onReject,
    this.avatarLoader,
  });

  final ContactDiscoveryEntry entry;
  final String Function(int count) friendsLabel;
  final String notRegisteredLabel;
  final String hiddenFriendCountLabel;
  final String inviteLabel;
  final String Function(FriendRelationship relationship) relationshipLabel;
  final VoidCallback onAdd;
  final VoidCallback onInvite;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final Future<String?> Function()? avatarLoader;

  @override
  Widget build(BuildContext context) {
    final candidate = entry.candidate;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (candidate == null)
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: context.colorScheme.onSurface.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.person_rounded,
                color: context.colorScheme.onSurfaceVariant,
                size: 30,
              ),
            )
          else
            UserAvatar(
              avatarUrl: candidate.avatarUrl,
              avatarLoader: avatarLoader,
              avatarRevision:
                  candidate.avatarStoragePath ?? candidate.avatarUrl,
              size: 54,
              borderRadius: 12,
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
                      ? notRegisteredLabel
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
          if (candidate == null)
            _InviteButton(label: inviteLabel, onTap: onInvite)
          else
            _CandidateAction(
              candidate: candidate,
              relationshipLabel: relationshipLabel,
              onAdd: onAdd,
              onAccept: onAccept,
              onReject: onReject,
            ),
        ],
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.onSurface.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          child: Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
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
          GlassIconButton(
            icon: Icons.close_rounded,
            onTap: onReject,
            width: 46,
            height: 42,
            borderRadius: 21,
            iconSize: 26,
          ),
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
