import 'package:flutter/material.dart';

/// Paint-only motion between bounded history windows. The list is laid out
/// at its final anchor from the first frame; pagination never starts motion.
class HistoryViewportTransition extends StatefulWidget {
  const HistoryViewportTransition({
    super.key,
    required this.revision,
    required this.fromOlder,
    required this.child,
    this.onCompleted,
  });

  final int revision;
  final bool fromOlder;
  final Widget child;
  final VoidCallback? onCompleted;

  @override
  State<HistoryViewportTransition> createState() =>
      HistoryViewportTransitionState();
}

class HistoryViewportTransitionState extends State<HistoryViewportTransition>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(
        vsync: this,
        value: 1,
        duration: const Duration(milliseconds: 240),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onCompleted?.call();
      });
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  bool get isAnimating => _controller.isAnimating;

  void finish() {
    if (_controller.value != 1) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant HistoryViewportTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) {
      if (MediaQuery.disableAnimationsOf(context)) {
        finish();
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) finish();
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          (widget.fromOlder ? -48 : 48) * (1 - _progress.value),
        ),
        child: child,
      ),
    ),
  );
}
