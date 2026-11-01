import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/theme/theme.dart';

class ProfileAmbientGlow extends StatelessWidget {
  const ProfileAmbientGlow({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.primary;
    return IgnorePointer(
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 42,
                sigmaY: 18,
                // This is the original broad halo. Its uncut blurred tail
                // owns the lower contour and the visible height of the glow.
                tileMode: ui.TileMode.decal,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .98),
                      color.withValues(alpha: .86),
                      color.withValues(alpha: .52),
                      color.withValues(alpha: .1),
                    ],
                    stops: const [0, .22, .65, 1],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    for (final alpha in AmbientGlowStyle.profileCoreAlpha)
                      color.withValues(alpha: alpha),
                  ],
                  stops: AmbientGlowStyle.profileCoreStops,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
