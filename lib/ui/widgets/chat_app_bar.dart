import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/utils/utils.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.userName,
    required this.isOnline,
    this.lastSeenAt,
    this.showsLastSeen = true,
    this.avatarUrl,
    this.avatarLoader,
    this.avatarRevision,
    this.avatarStoragePath,
    this.initialAvatarPath,
    this.profileId,
    this.onBack,
    this.onProfileTap,
  });

  final String userName;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool showsLastSeen;
  final String? avatarUrl;
  final Future<String?> Function()? avatarLoader;
  final Object? avatarRevision;
  final String? avatarStoragePath;
  final String? initialAvatarPath;
  final String? profileId;
  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    final onSurface = context.colorScheme.onSurface;
    final surface = context.colorScheme.surface;
    final statusText = _statusText(context);
    final onlineColor = AppColors.incomingBubble;
    final statusStyle = TextStyle(
      fontSize: 14,
      height: 1.2,
      color: isOnline ? onlineColor : onSurface,
      fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400,
    );

    return Padding(
      padding: EdgeInsets.only(
        top: systemPadding.top + 8,
        bottom: 8,
        left: systemPadding.left + 16,
        right: systemPadding.right + 16,
      ),
      child: Row(
        children: [
          GlassIconButton(
            chatStyle: true,
            icon: Icons.arrow_back_rounded,
            onTap: onBack ?? () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onProfileTap,
            child: ProfileAvatarHero(
              profileId: profileId,
              avatarUrl: avatarUrl,
              avatarStoragePath: avatarStoragePath,
              child: UserAvatar(
                avatarUrl: avatarUrl,
                initialAvatarPath: initialAvatarPath,
                preferAvatarLoader: true,
                avatarLoader: avatarLoader,
                avatarRevision: avatarRevision,
                size: 48,
                borderRadius: 10,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onProfileTap,
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
                  SizedBox(
                    width: double.infinity,
                    height: MediaQuery.textScalerOf(context).scale(14) * 1.2,
                    child: ConnectionStatusBuilder(
                      builder: (context, connecting) => AnimatedStatusSwitcher(
                        alignment: AlignmentDirectional.centerStart,
                        scaleAlignment: AlignmentDirectional.centerStart,
                        scaleBegin: 0.94,
                        duration: const Duration(milliseconds: 260),
                        child: connecting
                            ? FittedBox(
                                key: const ValueKey('connecting-status'),
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  context.l10n.connectionConnecting,
                                  style: statusStyle,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              )
                            : Text(
                                statusText,
                                key: ValueKey(statusText),
                                style: statusStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (isOnline) return context.l10n.chatOnlineStatus;
    if (!showsLastSeen) return context.l10n.chatOfflineStatus;
    final lastSeenAt = this.lastSeenAt;
    if (lastSeenAt == null) return context.l10n.chatOfflineStatus;
    return TimeFormatter.formatLastSeen(context, lastSeenAt);
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}
