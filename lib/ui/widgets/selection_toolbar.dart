import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

class SelectionToolbar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.isMuted,
    this.onToggleNotifications,
    this.onMarkAsRead,
    this.onDelete,
    this.isLoading = false,
  });

  final int selectedCount;
  final VoidCallback onClose;
  final bool isMuted;
  final VoidCallback? onToggleNotifications;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onDelete;
  final bool isLoading;

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
                  GlassButton(
                    icon: Icons.close_rounded,
                    onPressed: isLoading ? null : onClose,
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
                  if (isLoading)
                    const SizedBox.square(
                      dimension: 34,
                      child: Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    GlassButton(
                      icon: isMuted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_active_rounded,
                      onPressed: onToggleNotifications,
                    ),
                  const SizedBox(width: 12),
                  GlassButton(
                    icon: Icons.done_all_rounded,
                    onPressed: isLoading ? null : onMarkAsRead,
                  ),
                  const SizedBox(width: 12),
                  GlassButton(
                    icon: Icons.delete_outline_rounded,
                    onPressed: isLoading ? null : onDelete,
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
