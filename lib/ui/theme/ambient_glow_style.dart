/// Smooth bright core shared by upper and lower ambient glows.
abstract final class AmbientGlowStyle {
  static const _samples = 32;
  static final coreStops = <double>[
    for (var i = 0; i <= _samples; i++) .35 * i / _samples,
    1,
  ];
  static final coreAlpha = <double>[
    for (var i = 0; i <= _samples; i++) _strength(i / _samples),
    0,
  ];

  // Keep the profile's original low-intensity tail. The extra brightness is
  // composited over that field, not used to replace or crop it. Beyond .8 the
  // lower contour is the original one, including its full visible height.
  static final profileCoreStops = <double>[
    0,
    .22,
    .42,
    for (var i = 1; i <= _samples; i++) .22 + .58 * i / _samples,
    1,
  ]..sort();
  static final profileCoreAlpha = <double>[
    for (final t in profileCoreStops) _profileStrength(t),
  ];

  static double _profileStrength(double t) {
    final original = t <= .42
        ? .34 + (.22 - .34) * t / .42
        : .22 * (1 - t) / .58;
    final progress = ((t - .22) / .58).clamp(0.0, 1.0);
    final boost = 1 - progress * progress * (3 - 2 * progress);
    return original + (1 - original) * boost;
  }

  static double _strength(double t) {
    final remaining = 1 - t * t * (3 - 2 * t);
    return remaining * remaining * remaining;
  }
}
