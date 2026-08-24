import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class FriendCandidateItem extends StatefulWidget {
  const FriendCandidateItem({
    super.key,
    required this.candidate,
    required this.friendsLabel,
    required this.onAdd,
    required this.relationshipLabel,
    required this.onAccept,
    required this.onReject,
    this.avatarLoader,
  });

  final FriendCandidate candidate;
  final String Function(int count) friendsLabel;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final String Function(FriendRelationship relationship) relationshipLabel;
  final Future<String?> Function()? avatarLoader;

  @override
  State<FriendCandidateItem> createState() => _FriendCandidateItemState();
}

class _FriendCandidateItemState extends State<FriendCandidateItem> {
  Future<String?>? _avatarFuture;

  FriendCandidate get candidate => widget.candidate;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant FriendCandidateItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidate.avatarStoragePath != candidate.avatarStoragePath ||
        oldWidget.candidate.avatarUrl != candidate.avatarUrl) {
      _loadAvatar();
    }
  }

  void _loadAvatar() {
    _avatarFuture = candidate.avatarStoragePath?.isNotEmpty == true
        ? widget.avatarLoader?.call()
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
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
          FutureBuilder<String?>(
            future: _avatarFuture,
            builder: (context, snapshot) => UserAvatar(
              avatarUrl: snapshot.data ?? candidate.avatarUrl,
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
                      : '${widget.friendsLabel(candidate.friendCount!)} · @${candidate.username}',
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
              onTap: widget.onAdd,
            )
          else if (candidate.relationship == FriendRelationship.incoming) ...[
            PrimaryIconButton(
              icon: Icons.check_rounded,
              onTap: widget.onAccept,
              width: 54,
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.close_rounded,
              onTap: widget.onReject,
              width: 46,
              height: 42,
              borderRadius: 21,
              iconSize: 26,
            ),
          ] else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 108),
              child: Text(
                widget.relationshipLabel(candidate.relationship),
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
