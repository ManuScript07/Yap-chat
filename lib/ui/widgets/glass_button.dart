import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 24,
    this.borderRadius = 16,
    this.frostedStyle = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final double borderRadius;

  /// Opt in to the translucent, blurred material without changing other
  /// toolbars that use the original solid glass appearance.
  final bool frostedStyle;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.colorScheme.surface;

    if (frostedStyle) {
      return GestureDetector(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: ChatGlassSurface(
            borderRadius: borderRadius,
            lightStyle: true,
            child: Center(
              child: Icon(icon, color: backgroundColor, size: iconSize),
            ),
          ),
        ),
      );
    }

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
