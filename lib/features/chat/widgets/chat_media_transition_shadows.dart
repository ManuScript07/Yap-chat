import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';

import 'widgets.dart';

typedef ChatMediaShadowStyle = ({
  double topHeight,
  double bottomHeight,
  double bottomOffset,
  Color backgroundColor,
});

/// Fixed chat gradients, with a separate fade only over the moving photo.
/// Fading the entire overlay would briefly brighten the uncovered background
/// against the flight's independently darkening backdrop.
class ChatMediaTransitionShadows extends StatefulWidget {
  const ChatMediaTransitionShadows({
    super.key,
    required this.topHeight,
    required this.bottomHeight,
    required this.backgroundColor,
    this.bottomOffset = 0,
  });

  final double topHeight, bottomHeight, bottomOffset;
  final Color backgroundColor;

  ChatMediaShadowStyle get style => (
    topHeight: topHeight,
    bottomHeight: bottomHeight,
    bottomOffset: bottomOffset,
    backgroundColor: backgroundColor,
  );

  @override
  State<ChatMediaTransitionShadows> createState() =>
      _ChatMediaTransitionShadowsState();
}

class _ChatMediaTransitionShadowsState
    extends State<ChatMediaTransitionShadows> {
  final _viewportKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final flight = ChatMediaTransitionScope.maybeOf(context)?.localFlight;
    final edges = _EdgeShadows(style: widget.style);
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          key: _viewportKey,
          child: flight == null
              ? edges
              : AnimatedBuilder(
                  animation: flight,
                  child: edges,
                  builder: (_, edges) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Keep the fixed gradient elements mounted through
                        // both handoffs, including an immediate back gesture.
                        ClipPath(
                          clipper: _PhotoShadowClipper(
                            flight,
                            _viewportKey,
                            outside: true,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: edges,
                        ),
                        if (flight.isFlying)
                          ClipPath(
                            clipper: _PhotoShadowClipper(
                              flight,
                              _viewportKey,
                              outside: false,
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: _EdgeShadows(
                              style: widget.style,
                              opacity: flight.chromeOpacity.value,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _PhotoShadowClipper extends CustomClipper<Path> {
  const _PhotoShadowClipper(
    this.flight,
    this.viewport, {
    required this.outside,
  });
  final ChatMediaLocalFlight flight;
  final GlobalKey viewport;
  final bool outside;

  @override
  Path getClip(Size size) {
    final photo = flight.photoClipIn(viewport);
    final path = Path();
    if (outside) {
      path.fillType = PathFillType.evenOdd;
      path.addRect(Offset.zero & size);
    }
    if (photo != null) path.addRRect(photo);
    return path;
  }

  @override
  bool shouldReclip(_PhotoShadowClipper oldClipper) => true;
}

class _EdgeShadows extends StatelessWidget {
  const _EdgeShadows({required this.style, this.opacity = 1});
  final ChatMediaShadowStyle style;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        GradientOverlay(
          height: style.topHeight,
          isTop: true,
          // Fade shader colors directly, avoiding a fullscreen opacity buffer.
          backgroundColor: style.backgroundColor.withValues(
            alpha: style.backgroundColor.a * opacity,
          ),
        ),
        GradientOverlay(
          height: style.bottomHeight,
          bottomOffset: style.bottomOffset,
          isTop: false,
          backgroundColor: style.backgroundColor.withValues(
            alpha: style.backgroundColor.a * opacity,
          ),
        ),
      ],
    ),
  );
}
