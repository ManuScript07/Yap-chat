import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/glass_icon_button.dart';
import 'package:yap_chat/ui/widgets/user_avatar.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.userName,
    required this.isOnline,
    this.avatarUrl,
    this.onBack,
  });

  final String userName;
  final bool isOnline;
  final String? avatarUrl;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final onSurface = context.colorScheme.onSurface;
    final surface = context.colorScheme.surface;

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 8,
        bottom: 8,
        left: 16,
        right: 16,
      ),
      child: Row(
        children: [
          GlassIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack ?? () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 16),
          UserAvatar(
            avatarUrl: avatarUrl,
            size: 48,
            borderRadius: 10,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: surface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline
                      ? context.l10n.chatOnlineStatus
                      : context.l10n.chatOfflineStatus,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}
