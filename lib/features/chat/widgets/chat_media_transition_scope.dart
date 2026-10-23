import 'package:flutter/material.dart';

import 'widgets.dart';

/// Route-local geometry shared with the gallery without moving chat controls
/// into Navigator's overlay or rebuilding them during a photo flight.
class ChatMediaTransitionScope extends StatefulWidget {
  const ChatMediaTransitionScope({super.key, required this.child});

  final Widget child;

  static ChatMediaTransitionGeometry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_MediaTransitionOwner>()?.geometry;

  @override
  State<ChatMediaTransitionScope> createState() =>
      _ChatMediaTransitionScopeState();
}

class _ChatMediaTransitionScopeState extends State<ChatMediaTransitionScope> {
  final geometry = ChatMediaTransitionGeometry();

  @override
  void dispose() {
    geometry.shadows.dispose();
    geometry.localFlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MediaTransitionOwner(geometry: geometry, child: widget.child);
}

class _MediaTransitionOwner extends InheritedWidget {
  const _MediaTransitionOwner({required this.geometry, required super.child});
  final ChatMediaTransitionGeometry geometry;

  @override
  bool updateShouldNotify(_MediaTransitionOwner oldWidget) =>
      geometry != oldWidget.geometry;
}

enum ChatMediaChromeRegion { header, composer, scrollButton }

class ChatMediaTransitionGeometry {
  final localFlight = ChatMediaLocalFlight();
  final shadows = ValueNotifier<ChatMediaShadowStyle?>(null);
  // AnimatedSwitcher may keep an outgoing button alongside its replacement.
  // Register each mounted owner separately so disposing it cannot erase another.
  final _regions =
      <GlobalKey, ({ChatMediaChromeRegion region, double outset})>{};

  Iterable<Rect> _rects(ChatMediaChromeRegion region) sync* {
    for (final entry in _regions.entries) {
      if (entry.value.region != region) continue;
      final box = entry.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      yield MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ).inflate(entry.value.outset);
    }
  }

  Rect? _combinedRect(ChatMediaChromeRegion region) {
    Rect? result;
    for (final rect in _rects(region)) {
      result = result?.expandToInclude(rect) ?? rect;
    }
    return result;
  }

  Rect? get headerRect => _combinedRect(ChatMediaChromeRegion.header);
  Rect? get composerRect => _combinedRect(ChatMediaChromeRegion.composer);
  List<Rect> get scrollButtonRects =>
      _rects(ChatMediaChromeRegion.scrollButton).toList(growable: false);
}

/// Registers live chrome without changing its layout or animating it for media.
class ChatMediaTransitionChrome extends StatefulWidget {
  const ChatMediaTransitionChrome({
    super.key,
    required this.child,
    this.region = ChatMediaChromeRegion.header,
    this.paintOutset = 0,
  });
  final Widget child;
  final ChatMediaChromeRegion region;
  final double paintOutset;

  @override
  State<ChatMediaTransitionChrome> createState() =>
      _ChatMediaTransitionChromeState();
}

class _ChatMediaTransitionChromeState extends State<ChatMediaTransitionChrome> {
  final _regionKey = GlobalKey();
  ChatMediaTransitionGeometry? _geometry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final geometry = context
        .dependOnInheritedWidgetOfExactType<_MediaTransitionOwner>()
        ?.geometry;
    if (!identical(geometry, _geometry)) {
      _unbind();
      _geometry = geometry;
    }
    _updateGeometry();
  }

  @override
  void didUpdateWidget(ChatMediaTransitionChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateGeometry();
  }

  void _updateGeometry() {
    _geometry?._regions[_regionKey] = (
      region: widget.region,
      outset: widget.paintOutset,
    );
  }

  void _unbind() {
    _geometry?._regions.remove(_regionKey);
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _regionKey, child: widget.child);
    final flight = _geometry?.localFlight;
    return flight == null
        ? child
        : ValueListenableBuilder<double>(
            valueListenable: flight.chromeOpacity,
            child: child,
            builder: (_, value, child) => IgnorePointer(
              ignoring: value == 0,
              child: Opacity(opacity: value, child: child),
            ),
          );
  }
}
