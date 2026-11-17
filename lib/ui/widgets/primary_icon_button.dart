import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class PrimaryIconButton extends StatelessWidget {
  const PrimaryIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.width = 64,
    this.height = 42,
    this.iconSize = 26,
    this.muted = false,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final double iconSize;
  final bool muted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: muted
            ? colorScheme.onSurface.withValues(alpha: .20)
            : onTap == null
            ? colorScheme.primary.withValues(alpha: .45)
            : colorScheme.primary,
        borderRadius: BorderRadius.circular(height / 2),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(height / 2),
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: muted ? colorScheme.onSurface : colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
