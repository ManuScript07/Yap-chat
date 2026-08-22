import 'package:flutter/material.dart';

/// A restrained shared transition for presence and unread indicators.
class AnimatedStatusSwitcher extends StatelessWidget {
  const AnimatedStatusSwitcher({super.key, required this.child});

  static const _duration = Duration(milliseconds: 180);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _duration,
      reverseDuration: _duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.9, end: 1).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: child,
    );
  }
}
