import 'package:flutter/material.dart';

class ComposerReplyTransition extends StatelessWidget {
  const ComposerReplyTransition({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, outgoing) => Stack(
        alignment: Alignment.center,
        children: [
          for (final child in outgoing)
            IgnorePointer(child: ExcludeSemantics(child: child)),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}
