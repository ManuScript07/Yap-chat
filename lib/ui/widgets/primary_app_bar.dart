import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/core/core.dart';

abstract final class PrimaryHeaderGeometry {
  static const compactHeight = 106.0;
  static const compactTitleSize = 44.0;
  static const compactTabsHeight = 44.0;
  static const tabsTopSpacing = 4.0;
  static const tabsBottomSpacing = 8.0;
}

class PrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PrimaryAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.actionIcon,
    this.onActionPressed,
    this.compact = false,
    this.showGradient = true,
  });

  final String title;
  final Widget? titleWidget;
  final IconData? actionIcon;
  final VoidCallback? onActionPressed;
  final bool compact;
  final bool showGradient;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.scaffoldBackgroundColor;
    final iconColor = context.colorScheme.onSurface;

    return Container(
      height: preferredSize.height,
      width: double.infinity,
      decoration: showGradient
          ? BoxDecoration(
              gradient: GradientOverlay.topGradient(backgroundColor),
            )
          : null,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                // Roboto Flex's visible lowercase ink sits slightly below the
                // line-box center. Keep the button/header geometry unchanged.
                child: Transform.translate(
                  offset: Offset(
                    0,
                    actionIcon == null && !compact
                        ? 0
                        : -MediaQuery.textScalerOf(context).scale(2),
                  ),
                  child: titleWidget ?? _title(),
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
  Size get preferredSize =>
      Size.fromHeight(compact ? PrimaryHeaderGeometry.compactHeight : 130);

  Widget _title() {
    final text = Text(
      title,
      style: compact
          ? AppTextStyles.titleLargeFlex.copyWith(
              fontSize: PrimaryHeaderGeometry.compactTitleSize,
            )
          : AppTextStyles.titleLargeFlex,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return compact
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: text,
          )
        : text;
  }
}
