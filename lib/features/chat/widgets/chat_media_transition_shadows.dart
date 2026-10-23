import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';

import 'widgets.dart';

typedef ChatMediaShadowStyle = ({
  double topHeight,
  double bottomHeight,
  double bottomOffset,
  Color backgroundColor,
});

/// The same edge treatment on both sides of the photo transition. Fading these
/// gradients against an independently darkening backdrop creates a light pulse.
class ChatMediaTransitionShadows extends StatefulWidget {
  const ChatMediaTransitionShadows({
    super.key,
    required this.topHeight,
    required this.bottomHeight,
    required this.backgroundColor,
    this.bottomOffset = 0,
  });

  final double topHeight;
  final double bottomHeight;
  final double bottomOffset;
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
  ChatMediaTransitionGeometry? _geometry;
  bool _publishScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _geometry = ChatMediaTransitionScope.maybeOf(context);
    _publishStyle();
  }

  @override
  void didUpdateWidget(ChatMediaTransitionShadows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style != oldWidget.style) _publishStyle();
  }

  void _publishStyle() {
    if (_publishScheduled ||
        _geometry == null ||
        _geometry!.shadows.value == widget.style) {
      return;
    }
    _publishScheduled = true;
    // Layout/theme/keyboard changes can rebuild the covered chat while the
    // gallery is mounted. Never notify that sibling route during this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (mounted) _geometry?.shadows.value = widget.style;
    });
  }

  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: _EdgeShadows(style: widget.style));
}

/// Retains the chat's gradients at the route handoff, including albums/rotation.
/// Independent of gallery control visibility: toggling buttons must not restart
/// the edge treatment when the photo is closed.
class ChatMediaGalleryShadows extends StatelessWidget {
  const ChatMediaGalleryShadows({super.key, required this.geometry});

  final ChatMediaTransitionGeometry geometry;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ValueListenableBuilder<ChatMediaShadowStyle?>(
      valueListenable: geometry.shadows,
      builder: (_, style, _) =>
          style == null ? const SizedBox() : _EdgeShadows(style: style),
    ),
  );
}

class _EdgeShadows extends StatelessWidget {
  const _EdgeShadows({required this.style});
  final ChatMediaShadowStyle style;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        GradientOverlay(
          height: style.topHeight,
          isTop: true,
          backgroundColor: style.backgroundColor,
        ),
        GradientOverlay(
          height: style.bottomHeight,
          bottomOffset: style.bottomOffset,
          isTop: false,
          backgroundColor: style.backgroundColor,
        ),
      ],
    ),
  );
}
