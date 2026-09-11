import 'package:flutter/material.dart';

class GradientOverlay extends StatelessWidget {
  const GradientOverlay({
    super.key,
    required this.height,
    required this.isTop,
    required this.backgroundColor,
    this.bottomOffset = 0,
  });

  final double height;
  final bool isTop;
  final Color backgroundColor;
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : bottomOffset,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [backgroundColor, backgroundColor.withValues(alpha: 0.0)],
            ),
          ),
        ),
      ),
    );
  }
}
