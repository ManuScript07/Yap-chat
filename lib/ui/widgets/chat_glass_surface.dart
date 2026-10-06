import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

/// Shared frosted material, independent of layout and input behavior.
class ChatGlassSurface extends StatelessWidget {
  const ChatGlassSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.lightStyle = false,
  });

  // Preserve the space previously occupied by the 1.5px border. The new
  // thinner, painted border must not change composer/message-list geometry.
  static const contentInset = 1.5;
  static final _blur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  final double borderRadius;
  final Widget child;

  /// The profile keeps its milky-white tint; chats use the smoky tint by default.
  final bool lightStyle;

  @override
  Widget build(BuildContext context) {
    final foreground = context.colorScheme.onSurface;
    final background = context.scaffoldBackgroundColor;
    final radius = math.max(0.0, borderRadius);
    final innerRadius = math.max(0.0, radius - contentInset);
    final tint = lightStyle
        ? Colors.transparent
        : background.withValues(alpha: 0.10);

    return CustomPaint(
      foregroundPainter: _GlassRimPainter(radius, foreground, lightStyle),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: (lightStyle ? foreground : background).withValues(
                alpha: 0.12,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(contentInset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: BackdropFilter(
              filter: _blur,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                        foreground.withValues(alpha: lightStyle ? 0.40 : 0.18),
                        tint,
                      ),
                      Color.alphaBlend(
                        foreground.withValues(alpha: lightStyle ? 0.32 : 0.12),
                        tint,
                      ),
                    ],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A subtle top highlight without another filter, layer, or layout inset.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter(this.radius, this.color, this.lightStyle);

  final double radius;
  final Color color;
  final bool lightStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const strokeWidth = 1.0;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: lightStyle ? 0.80 : 0.40),
          color.withValues(alpha: lightStyle ? 0.45 : 0.20),
          color.withValues(alpha: lightStyle ? 0.22 : 0.08),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.max(0.0, radius - strokeWidth / 2)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      color != oldDelegate.color ||
      lightStyle != oldDelegate.lightStyle;
}
