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
    final isOnline = chat.blockedByPeer
        ? false
        : chat.peerId.isEmpty
        ? chat.isOnline
        : context.select<PresenceCubit, bool>(
            (cubit) => cubit.state.isOnline(chat.peerId),
          );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                avatarUrl: chat.avatarUrl,
                avatarStoragePath: chat.avatarStoragePath,
                child: UserAvatar(
                  avatarUrl: chat.avatarUrl,
                  avatarLoader: avatarLoader,
                  avatarRevision: chat.avatarStoragePath ?? chat.avatarUrl,
                  size: 56,
                  borderRadius: 10,
                  isOnline: isOnline,
                  showOnlineBadge: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildChatInfo(context)),
              const SizedBox(width: 16),
              _buildMetadata(context),
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
        Text(
          chat.userName,
          style: AppTextStyles.chatName.copyWith(color: primaryTextColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
