import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class SelectionToolbar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.isMuted,
    this.onToggleNotifications,
    this.onMarkAsRead,
    this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onClose;
  final bool isMuted;
  final VoidCallback? onToggleNotifications;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final brandPrimary = context.colorScheme.primary;

    return Container(
      height: preferredSize.height,
      width: double.infinity,
      color: brandPrimary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  _GlassButton(
                    icon: Icons.close_rounded,
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$selectedCount',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  _GlassButton(
                    icon: isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                    onPressed: onToggleNotifications,
                  ),
                  const SizedBox(width: 12),
                  _GlassButton(
                    icon: Icons.done_all_rounded,
                    onPressed: onMarkAsRead,
                  ),
                  const SizedBox(width: 12),
                  _GlassButton(
                    icon: Icons.delete_outline_rounded,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(130);
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.colorScheme.surface;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: backgroundColor.withValues(alpha: 0.8),
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: backgroundColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}
