import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

class AddFriendMethodTile extends StatelessWidget {
  const AddFriendMethodTile({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.colorScheme.primary.withValues(
                    alpha: enabled ? 1 : 0.45,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  color: context.colorScheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.chatName.copyWith(
                    color: enabled
                        ? context.colorScheme.onSurface
                        : context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colorScheme.onSurfaceVariant,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
