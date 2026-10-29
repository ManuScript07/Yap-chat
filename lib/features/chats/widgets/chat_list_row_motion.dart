import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Paint-only movement: keyed row/image state and sliver geometry stay intact.
class ChatListRowMotion extends SingleChildRenderObjectWidget {
  const ChatListRowMotion({
    super.key,
    required this.progress,
    this.originY,
    this.entering = false,
    this.scrollDisplacement,
    required super.child,
  });

  final Animation<double> progress;
  final double? originY;
  final bool entering;

  /// User scrolling after motion started moves both endpoints together.
  final ValueGetter<double>? scrollDisplacement;

  static double visualTopOf(RenderBox box) =>
      box.localToGlobal(Offset.zero).dy +
      (box is _RenderChatListRowMotion ? box.translation : 0);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderChatListRowMotion(progress, originY, entering, scrollDisplacement);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _RenderChatListRowMotion).update(
    progress,
    originY,
    entering,
    scrollDisplacement,
  );
}

class _RenderChatListRowMotion extends RenderProxyBox {
  _RenderChatListRowMotion(
    this._progress,
    this._originY,
    this._entering,
    this._scrollDisplacement,
  );
  Animation<double> _progress;
  double? _originY;
  bool _entering;
  ValueGetter<double>? _scrollDisplacement;
  double translation = 0;
  final _opacity = LayerHandle<OpacityLayer>();
  @override
  bool get alwaysNeedsCompositing => child != null;

  void update(
    Animation<double> progress,
    double? origin,
    bool entering,
    ValueGetter<double>? scrollDisplacement,
  ) {
    if (!identical(_progress, progress)) {
      if (attached) _progress.removeListener(_tick);
      _progress = progress;
      if (attached) _progress.addListener(_tick);
    }
    _originY = origin;
    _entering = entering;
    _scrollDisplacement = scrollDisplacement;
    _tick();
  }

  void _tick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_tick);
  }

  @override
  void detach() {
    _progress.removeListener(_tick);
    super.detach();
  }

  @override
  void dispose() {
    _opacity.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final progress = Curves.easeOutCubic.transform(_progress.value);
    // Re-evaluate after the viewport's existing anchor correction; do not
    // replay the pre-correction scroll displacement on the following frame.
    translation = _originY == null
        ? 0
        : (_originY! -
                  (_scrollDisplacement?.call() ?? 0) -
                  localToGlobal(Offset.zero).dy) *
              (1 - progress);
    final alpha = _entering ? (255 * progress).round() : 255;
    void paintChild(PaintingContext context, Offset offset) {
      if (child != null) {
        context.paintChild(child!, offset + Offset(0, translation));
      }
    }

    if (alpha < 255) {
      _opacity.layer = context.pushOpacity(
        offset,
        alpha,
        paintChild,
        oldLayer: _opacity.layer,
      );
    } else {
      _opacity.layer = null;
      paintChild(context, offset);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, translation, 0, 1);
  }
}
