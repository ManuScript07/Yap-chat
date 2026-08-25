import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/core/core.dart';

class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PrimaryAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.actionIcon,
    this.onActionPressed,
  });

  final String title;
  final Widget? titleWidget;
  final IconData? actionIcon;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.scaffoldBackgroundColor;
    final iconColor = context.colorScheme.onSurface;

    return Container(
      height: preferredSize.height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            backgroundColor,
            backgroundColor,
            backgroundColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child:
                    titleWidget ??
                    Text(
                      title,
                      style: AppTextStyles.titleLargeFlex,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              ),
              if (actionIcon != null)
                SizedBox(
                  width: 42,
                  height: 42,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(actionIcon, color: iconColor, size: 42),
                    onPressed: onActionPressed,
                  ),
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
