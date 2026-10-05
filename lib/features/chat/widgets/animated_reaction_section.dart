import 'package:flutter/material.dart';

/// Reserves space vertically without stretching emoji or animating width.
/// Keeps the outgoing content alive until the closing animation completes.
class AnimatedReactionSection extends StatefulWidget {
  const AnimatedReactionSection({
    super.key,
    required this.visible,
    required this.child,
    this.reservedBottom = 0,
  });
  final bool visible;
  final Widget child;

  /// Unanimated footer space that revealed content must not paint into.
  /// Used when a narrow text bubble puts its status below the reaction row.
  final double reservedBottom;
  @override
  State<AnimatedReactionSection> createState() =>
      _AnimatedReactionSectionState();
}

class _AnimatedReactionSectionState extends State<AnimatedReactionSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.visible ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  Widget? _content;
  double _reservedBottom = 0;
  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _content = widget.child;
      _reservedBottom = widget.reservedBottom;
    }
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _content = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedReactionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      _content = widget.child;
      _reservedBottom = widget.reservedBottom;
      _controller.forward();
    } else if (oldWidget.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_content == null) return const SizedBox.shrink();
    return ClipRect(
      clipper: _reservedBottom > 0
          ? _ReactionRevealClipper(_reservedBottom)
          : null,
      child: SizeTransition(
        alignment: Alignment.topLeft,
        fixedCrossAxisSizeFactor: 1,
        sizeFactor: _progress,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: FadeTransition(
            opacity: _progress,
            child: ScaleTransition(
              alignment: Alignment.topLeft,
              scale: Tween<double>(begin: .92, end: 1).animate(_progress),
              child: _content,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionRevealClipper extends CustomClipper<Rect> {
  const _ReactionRevealClipper(this.reservedBottom);
  final double reservedBottom;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    0,
    size.width,
    (size.height - reservedBottom).clamp(0.0, size.height),
  );

  @override
  bool shouldReclip(_ReactionRevealClipper oldClipper) =>
      oldClipper.reservedBottom != reservedBottom;
}
