import 'package:flutter/material.dart';

/// A restrained shared transition for presence and unread indicators.
class AnimatedStatusSwitcher extends StatelessWidget {
  const AnimatedStatusSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.scaleTransition = true,
    this.duration = _duration,
    this.scaleBegin = 0.9,
    this.scaleAlignment = Alignment.center,
  });

  static const _duration = Duration(milliseconds: 180);

  final Widget child;
  final AlignmentGeometry alignment;
  final bool scaleTransition;
  final Duration duration;
  final double scaleBegin;
  // Layout and transform anchors are separate: chat labels need both at
  // centerStart so scaling never introduces a horizontal drift.
  final AlignmentGeometry scaleAlignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(
          begin: scaleBegin,
          end: 1,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: scaleTransition
              ? ScaleTransition(
                  scale: scale,
                  alignment: scaleAlignment.resolve(Directionality.of(context)),
                  child: child,
                )
              : child,
        );
      },
      child: child,
    );
  }
}
