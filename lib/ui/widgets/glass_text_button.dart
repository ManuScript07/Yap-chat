import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class GlassTextButton extends StatelessWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 42,
    this.horizontalPadding = 18,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;
  final double horizontalPadding;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundColor ?? context.colorScheme.onSurface;
    return Material(
      color: backgroundColor ?? foreground.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(height / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              child: Text(
                label,
                style: context.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
