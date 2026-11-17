import 'package:flutter/material.dart';

class MediaGalleryRoute extends PageRouteBuilder<void> {
  MediaGalleryRoute({
    required super.pageBuilder,
    super.transitionsBuilder = fade,
  }) : super(
         transitionDuration: const Duration(milliseconds: 260),
         reverseTransitionDuration: const Duration(milliseconds: 180),
       );

  // Hero temporarily completes ModalRoute.animation while measuring the
  // destination offstage. The controller tracks the visible transition.
  Animation<double> get mediaAnimation => controller!.view;

  static Widget fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
    child: child,
  );
}
