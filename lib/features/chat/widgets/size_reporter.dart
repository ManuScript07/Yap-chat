import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSizeChanged, super.child});

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSizeReporter(onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderSizeReporter).onSizeChanged = onSizeChanged;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _previousSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _previousSize) return;
    _previousSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSizeChanged(size);
    });
  }
}
