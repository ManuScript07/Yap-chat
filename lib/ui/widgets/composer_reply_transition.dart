import 'package:flutter/material.dart';

class ComposerReplyTransition extends StatelessWidget {
  const ComposerReplyTransition({
    super.key,
    required this.child,
    this.fadeOutInPlace = false,
  });

  final Widget? child;
  final bool fadeOutInPlace;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    final transition = AnimatedSwitcher(
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
        child: fadeOutInPlace
            ? child
            : SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child,
              ),
      ),
      child: child,
    );
    if (!fadeOutInPlace) return transition;
    // The switcher keeps the outgoing panel at full height while it fades.
    // Resize the empty space after the panel has stopped painting.
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.bottomCenter,
      curve: Curves.easeOutCubic,
      child: transition,
    );
  }
}
