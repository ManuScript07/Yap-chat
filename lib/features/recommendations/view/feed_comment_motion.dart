import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const feedCommentMotionDuration = Duration(milliseconds: 180);

typedef FeedCommentScrollAnchor = ({int index, double offset});

/// Corrects the viewport during layout, before the reordered list is painted.
class FeedCommentList extends SliverList {
  const FeedCommentList({super.key, required super.delegate, this.anchor});

  final FeedCommentScrollAnchor? anchor;

  @override
  RenderSliverList createRenderObject(BuildContext context) =>
      _RenderFeedCommentList(
        childManager: context as SliverMultiBoxAdaptorElement,
      )..anchor = anchor;

  @override
  void updateRenderObject(BuildContext context, RenderSliverList renderObject) {
    (renderObject as _RenderFeedCommentList).anchor = anchor;
  }
}

class _RenderFeedCommentList extends RenderSliverList {
  _RenderFeedCommentList({required super.childManager});

  FeedCommentScrollAnchor? _anchor;
  int _attempts = 0;

  set anchor(FeedCommentScrollAnchor? value) {
    if (_anchor == value) return;
    _anchor = value;
    _attempts = 0;
    if (value != null) markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final target = _anchor;
    if (target == null || geometry!.scrollOffsetCorrection != null) return;
    if (++_attempts > 3 || firstChild == null) {
      _anchor = null;
      return;
    }

    double? actual;
    for (var row = firstChild; row != null; row = childAfter(row)) {
      if (indexOf(row) == target.index) {
        actual = childScrollOffset(row);
        break;
      }
    }
    if (actual != null) {
      _anchor = null;
    } else {
      // Re-ranking may move a retained row outside the current layout window.
      // Use the measured window to approach it without laying out all rows.
      final first = firstChild!;
      final last = lastChild!;
      final start = childScrollOffset(first)!;
      final span = childScrollOffset(last)! + paintExtentOf(last) - start;
      final mean = span / (indexOf(last) - indexOf(first) + 1);
      actual = (start + (target.index - indexOf(first)) * mean).clamp(
        0.0,
        geometry!.scrollExtent,
      );
    }

    final correction = actual - constraints.scrollOffset - target.offset;
    if (correction.abs() > 0.5 && correction.isFinite) {
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
    }
  }
}

class FeedCommentEntrance extends StatefulWidget {
  const FeedCommentEntrance({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<FeedCommentEntrance> createState() => _FeedCommentEntranceState();
}

class _FeedCommentEntranceState extends State<FeedCommentEntrance> {
  late final bool _animate = widget.animate;

  @override
  Widget build(BuildContext context) => !_animate
      ? widget.child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : feedCommentMotionDuration,
          curve: Curves.easeOutCubic,
          child: widget.child,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - value)),
              child: child,
            ),
          ),
        );
}
