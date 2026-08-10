import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.width = 50,
    this.height = 50,
    this.borderRadius = 20,
    this.iconSize = 32,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final mainColor = context.colorScheme.onSurface;

    final outerRadius = math.max(0.0, borderRadius);
    final innerRadius = math.max(0.0, borderRadius - 1.5);

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerRadius),
          border: Border.all(
            color: mainColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(innerRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Material(
              color: mainColor.withValues(alpha: 0.15),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(innerRadius),
                child: Center(
                  child: Icon(
                    icon,
                    color: mainColor,
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}