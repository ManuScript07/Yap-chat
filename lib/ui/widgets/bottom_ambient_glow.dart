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

  @override
  Widget build(BuildContext context) {
    final baseColor = glowColor ?? context.colorScheme.primary;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma * 1.5,
                    sigmaY: blurSigma * 0.6,
                    tileMode: TileMode.decal,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          baseColor.withValues(alpha: opacity),
                          baseColor.withValues(alpha: opacity * 0.6),
                          baseColor.withValues(alpha: opacity * 0.15),
                          baseColor.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.4, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: height * 0.2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        baseColor.withValues(alpha: 1.0),
                        baseColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
