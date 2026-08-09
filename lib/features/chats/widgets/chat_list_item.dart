import 'package:flutter/material.dart';
import 'package:yap_chat/utils/utils.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/core/core.dart';

class ChatListItem extends StatelessWidget {
  const ChatListItem({
    super.key,
    required this.chat,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final Chat chat;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;


  @override
  Widget build(BuildContext context) {
    final selectionColor = context.colorScheme.primary.withValues(alpha: 0.1);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isSelected ? selectionColor : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
            _buildAvatar(context),
            const SizedBox(width: 16),
            Expanded(
              child: _buildChatInfo(context),
            ),
            const SizedBox(width: 16),
            _buildMetadata(context),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final surfaceColor = context.colorScheme.primary;
    final secondaryTextColor = context.colorScheme.onSurface;

    final primaryBrandColor = context.colorScheme.primary;
    final backgroundColor = context.scaffoldBackgroundColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 56,
            height: 56,
            color: surfaceColor,
            child: chat.avatarUrl != null
                ? Image.network(
                  chat.avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.person,
                    color: secondaryTextColor,
                    size: 36,
                  ),
                )
                : Icon(
                  Icons.person,
                  color: secondaryTextColor,
                  size: 36,
                ),
          ),
        ),
        if (chat.isOnline)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: primaryBrandColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: backgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatInfo(BuildContext context) {

    final messagePrefix = chat.isLastMessageFromMe ? context.l10n.chatsMessagePrefixYou : '';
    final primaryTextColor = context.colorScheme.onSurface;
    final secondaryTextColor = context.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chat.userName,
          style: AppTextStyles.chatName.copyWith(
            color: primaryTextColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '$messagePrefix${chat.lastMessage}',
          style: AppTextStyles.messagePreview.copyWith(
            color: secondaryTextColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final secondaryTextColor = context.colorScheme.onSurfaceVariant;
    final primaryBrandColor = context.colorScheme.primary;
    final badgeTextColor = context.scaffoldBackgroundColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          TimeFormatter.format(context, chat.lastMessageTime),
          style: AppTextStyles.metadata.copyWith(
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 8),
        if (chat.unreadCount > 0)
          Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: primaryBrandColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${chat.unreadCount}',
              style: AppTextStyles.badgeText.copyWith(
                color: badgeTextColor,
              ),
            ),
          )
        else
          const SizedBox(height: 25),
      ],
    );
  }
}
