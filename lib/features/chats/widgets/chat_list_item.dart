import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/utils/utils.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';

class ChatListItem extends StatelessWidget {
  const ChatListItem({
    super.key,
    required this.chat,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.avatarLoader,
  });

  final Chat chat;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final Future<String?> Function()? avatarLoader;

  @override
  Widget build(BuildContext context) {
    final selectionColor = context.colorScheme.primary.withValues(alpha: 0.1);
    final systemPadding = MediaQuery.paddingOf(context);
    final canShowAvatar =
        !chat.blockedByPeer &&
        !chat.peerIsGloballyBanned &&
        !chat.peerIsDeleted;
    final isOnline =
        chat.blockedByPeer || chat.peerIsGloballyBanned || chat.peerIsDeleted
        ? false
        : chat.peerId.isEmpty
        ? chat.isOnline
        : context.select<PresenceCubit, bool>(
            (cubit) => cubit.state.isOnline(chat.peerId),
          );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      child: Container(
        color: isSelected ? selectionColor : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16 + systemPadding.left,
            right: 16 + systemPadding.right,
            top: 14,
            bottom: 14,
          ),
          child: Row(
            children: [
              ProfileAvatarHero(
                profileId: chat.peerId,
                avatarUrl: canShowAvatar ? chat.avatarUrl : null,
                avatarStoragePath: canShowAvatar
                    ? chat.avatarStoragePath
                    : null,
                child: UserAvatar(
                  avatarUrl: canShowAvatar ? chat.avatarUrl : null,
                  initialAvatarPath: canShowAvatar
                      ? chat.cachedAvatarPath
                      : null,
                  preferAvatarLoader: true,
                  avatarLoader: canShowAvatar ? avatarLoader : null,
                  avatarRevision: canShowAvatar
                      ? chat.avatarStoragePath ?? chat.avatarUrl
                      : null,
                  size: 56,
                  borderRadius: 10,
                  isOnline: isOnline,
                  showOnlineBadge: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      Expanded(child: _buildChatInfo(context)),
                      const SizedBox(width: 16),
                      // Large localized dates must leave space for the name
                      // and its fixed-width mute indicator.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .55,
                        ),
                        child: _buildMetadata(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatInfo(BuildContext context) {
    final messagePrefix = chat.isLastMessageFromMe
        ? "${context.l10n.chatsMessagePrefixYou}: "
        : '';
    final primaryTextColor = context.colorScheme.onSurface;
    final secondaryTextColor = context.colorScheme.onSurfaceVariant;

    final preview = switch (chat.lastMessageType) {
      ChatPreviewType.image => context.l10n.chatReplyPhoto,
      ChatPreviewType.audio => context.l10n.chatReplyAudio,
      ChatPreviewType.location => context.l10n.chatReplyLocation,
      ChatPreviewType.text => chat.lastMessage,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                chat.userName,
                style: AppTextStyles.chatName.copyWith(color: primaryTextColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.isMuted) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.notifications_off_rounded,
                size: 16,
                color: secondaryTextColor,
                semanticLabel: context.l10n.chatsNotificationsDisabled,
              ),
            ],
          ],
        ),
        if (!chat.peerIsGloballyBanned && !chat.peerIsDeleted)
          AnimatedStatusSwitcher(
            child: Text(
              '$messagePrefix$preview',
              key: ValueKey('$messagePrefix$preview'),
              style: AppTextStyles.messagePreview.copyWith(
                color: secondaryTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    if (chat.peerIsGloballyBanned || chat.peerIsDeleted) {
      return const SizedBox.shrink();
    }
    final secondaryTextColor = context.colorScheme.onSurfaceVariant;
    final badgeColor = chat.isMuted
        ? context.colorScheme.onSurfaceVariant
        : context.colorScheme.primary;
    final badgeTextColor = context.scaffoldBackgroundColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          TimeFormatter.format(context, chat.lastMessageTime),
          style: AppTextStyles.metadata.copyWith(color: secondaryTextColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        AnimatedUnreadBadge(
          count: chat.unreadCount,
          color: badgeColor,
          textColor: badgeTextColor,
        ),
      ],
    );
  }
}
