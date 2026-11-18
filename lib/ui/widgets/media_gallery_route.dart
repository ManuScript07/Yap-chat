import 'package:flutter/material.dart';

class MediaGalleryRoute extends PageRouteBuilder<void> {
  MediaGalleryRoute({
    required super.pageBuilder,
    super.transitionsBuilder = fade,
    this.separateBackground = false,
  }) : super(
         transitionDuration: const Duration(milliseconds: 260),
         reverseTransitionDuration: const Duration(milliseconds: 180),
       );

  final bool separateBackground;
  CurvedAnimation? _backgroundFade;
  ProxyAnimation? _heroAnimation;

  @override
  Animation<double>? get animation {
    final routeAnimation = super.animation;
    if (!separateBackground || routeAnimation == null) return routeAnimation;
    return _heroAnimation ??= ProxyAnimation(routeAnimation);
  }

  // Hero temporarily completes ModalRoute.animation while measuring the
  // destination offstage. The controller tracks the visible transition.
  Animation<double> get mediaAnimation => controller!.view;

  static const openingFade = Curves.easeOutCubic;
  static const closingFade = Curves.easeInCubic;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!separateBackground) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    final opacity = _backgroundFade ??= CurvedAnimation(
      parent: mediaAnimation,
      curve: openingFade,
      reverseCurve: closingFade,
    );
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: opacity,
          builder: (context, _) => ColoredBox(
            key: const ValueKey('media-gallery-backdrop'),
            color: background.withValues(alpha: opacity.value),
          ),
        ),
        // A matched Hero paints above this page. This fade is also used when
        // its source is offscreen and there is no matching return tile.
        FadeTransition(opacity: opacity, child: child),
      ],
    );
  }

  @override
  void dispose() {
    // removeRoute can dispose a forward animation without a reverse tick.
    // End any flight before releasing the preview used by its overlay.
    _heroAnimation?.parent = kAlwaysDismissedAnimation;
    _backgroundFade?.dispose();
    super.dispose();
  }

  static Widget fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: animation.drive(CurveTween(curve: openingFade)),
    child: child,
  );
}
