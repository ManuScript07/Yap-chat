import 'package:flutter/material.dart';

/// Fixed-width dots animate independently of the label and its surroundings.
class AnimatedConnectingText extends StatefulWidget {
  const AnimatedConnectingText({
    super.key,
    required this.label,
    required this.style,
  });

  final String label;
  final TextStyle style;

  @override
  State<AnimatedConnectingText> createState() => _AnimatedConnectingTextState();
}

class _AnimatedConnectingTextState extends State<AnimatedConnectingText>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final _first = _opacity(0, 76).animate(_controller);
  late final _second = _opacity(18, 58).animate(_controller);
  late final _third = _opacity(48, 28).animate(_controller);

  // Each dot fades in, including the first; all three reset smoothly together.
  static Animatable<double> _opacity(double before, double after) =>
      TweenSequence<double>([
        if (before > 0)
          TweenSequenceItem(tween: ConstantTween(0), weight: before),
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 12,
        ),
        TweenSequenceItem(tween: ConstantTween(1), weight: after),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 12,
        ),
      ]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Visibility.of(context) || !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = .7;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.label.replaceFirst(RegExp(r'[.…]+$'), '');
    return Semantics(
      label: widget.label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(word, style: widget.style, maxLines: 1, softWrap: false),
            RepaintBoundary(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _first,
                    child: Text('.', style: widget.style),
                  ),
                  FadeTransition(
                    opacity: _second,
                    child: Text('.', style: widget.style),
                  ),
                  FadeTransition(
                    opacity: _third,
                    child: Text('.', style: widget.style),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
