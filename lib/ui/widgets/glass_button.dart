import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 24,
    this.borderRadius = 16,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.colorScheme.surface;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: backgroundColor.withValues(alpha: 0.8),
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(icon, color: backgroundColor, size: iconSize),
        ),
      ),
    );
  }
}
