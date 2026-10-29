import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared by the bar and every control placed immediately above it.
abstract final class FloatingNavigationGeometry {
  static const height = 64.0;
  static const bottomOffset = 10.0;
  static const controlSpacing = 16.0;

  static double heightFor(MediaQueryData media) =>
      math.max(height, 30 + 3 + media.textScaler.scale(12) * 1.1 + 10);

  // Landscape navigation buttons occupy the side inset, as before.
  static double systemBottom(MediaQueryData media) =>
      media.orientation == Orientation.landscape ? 0 : media.viewPadding.bottom;

  static double occupiedHeight(MediaQueryData media) =>
      systemBottom(media) + bottomOffset + heightFor(media);
}
