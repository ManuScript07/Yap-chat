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
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: onTap == null
            ? colorScheme.primary.withValues(alpha: 0.45)
            : colorScheme.primary,
        borderRadius: BorderRadius.circular(height / 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height / 2),
          child: Center(
            child: Icon(icon, size: iconSize, color: colorScheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
