import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

/// Виджет мягкого атмосферного свечения внизу экрана.
class BottomAmbientGlow extends StatelessWidget {
  const BottomAmbientGlow({
    super.key,
    this.glowColor,
    this.height = 180.0,
    this.blurSigma = 40.0,
    this.opacity = 1,
  });

  final Color? glowColor;
  final double height;
  final double blurSigma;
  final double opacity;

  static const _coreSamples = 32;
  static final _coreStops = <double>[
    for (var i = 0; i <= _coreSamples; i++) .35 * i / _coreSamples,
    1,
  ];
  static final _coreAlpha = <double>[
    for (var i = 0; i <= _coreSamples; i++) _coreStrength(i / _coreSamples),
    0,
  ];

  static double _coreStrength(double t) {
    final remaining = 1 - t * t * (3 - 2 * t);
    return remaining * remaining * remaining;
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = glowColor ?? context.colorScheme.primary;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Opacity(
            opacity: opacity,
            child: Stack(
              children: [
                Positioned.fill(
                  // Preserve the original broad halo and its rounded falloff.
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: blurSigma * 1.5,
                      sigmaY: blurSigma * .6,
                      tileMode: TileMode.decal,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            baseColor.withValues(alpha: 1),
                            baseColor.withValues(alpha: .6),
                            baseColor.withValues(alpha: .15),
                            baseColor.withValues(alpha: 0),
                          ],
                          stops: const [0, .4, .6, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  // A bright core is required at the base. Its slope fades to
                  // zero at both ends instead of ending as a narrow hard strip.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          for (final alpha in _coreAlpha)
                            baseColor.withValues(alpha: alpha),
                        ],
                        stops: _coreStops,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
