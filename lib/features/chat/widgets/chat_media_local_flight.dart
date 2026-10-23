import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'widgets.dart';

Rect? _bounds(GlobalKey? key) {
  // All anchors are keyed RenderObjectWidgets (ClipRRect/SizedBox). A route
  // can deactivate its element before State.dispose unregisters the anchor.
  // findRenderObject is illegal then; the detached render object is safe to
  // inspect and reject without traversing an inactive element.
  final element = key?.currentContext;
  if (element is! RenderObjectElement) return null;
  final box = element.renderObject;
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

class _PhotoAnchor {
  const _PhotoAnchor(
    this.key,
    this.path,
    this.cacheWidth,
    this.radius,
    this.hidden,
  );
  final GlobalKey key;
  final String path;
  final int? cacheWidth;
  final BorderRadius radius;
  final ValueNotifier<bool>? hidden;
  Rect? get rect => _bounds(key);
}

/// A single moving photo in the chat Stack, not a partitioned Navigator Hero.
/// Uses the existing route animation; no extra controller, navigator or timer.
class ChatMediaLocalFlight extends ChangeNotifier {
  final _sources = <String, _PhotoAnchor>{};
  final _destinations = <String, _PhotoAnchor>{};
  final chromeOpacity = ValueNotifier<double>(1);
  GlobalKey? _hostKey;
  Animation<double>? _animation;
  CurvedAnimation? _fade;
  Rect? _sourceRect;
  String? _tag;
  double? _initialRatio;
  bool _local = false;
  bool _disposed = false;
  ValueNotifier<bool>? _hiddenSource;

  bool get hasHost => _hostKey != null;
  bool get isFlying =>
      _local &&
      hasHost &&
      _sources.containsKey(_tag) &&
      (_animation?.status == AnimationStatus.forward ||
          _animation?.status == AnimationStatus.reverse);
  double get progress => (_animation?.value ?? 0).clamp(0.0, 1.0);

  void register({
    required String tag,
    required GlobalKey key,
    required String path,
    required int? cacheWidth,
    required BorderRadius radius,
    required bool gallery,
    ValueNotifier<bool>? hidden,
  }) {
    (gallery ? _destinations : _sources)[tag] = _PhotoAnchor(
      key,
      path,
      cacheWidth,
      radius,
      hidden,
    );
  }

  void unregister(String tag, GlobalKey key, {required bool gallery}) {
    final anchors = gallery ? _destinations : _sources;
    final anchor = anchors[tag];
    if (!identical(anchor?.key, key)) return;
    if (identical(_hiddenSource, anchor?.hidden)) _hiddenSource = null;
    anchors.remove(tag);
  }

  /// After Navigator.push, outside build and before its first painted frame.
  void follow(
    Animation<double> animation, {
    required String tag,
    double? ratio,
  }) {
    _detach();
    _animation = animation;
    _tag = tag;
    _initialRatio = ratio;
    _sourceRect = _sources[tag]?.rect;
    _fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _local =
        hasHost &&
        ratio != null &&
        ratio.isFinite &&
        ratio > 0 &&
        _sourceRect?.isEmpty == false;
    animation.addListener(_tick);
    animation.addStatusListener(_statusChanged);
    _tick();
  }

  void select(String tag) => _tag = tag;
  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _local =
          hasHost &&
          _sources[_tag]?.rect != null &&
          _destinations[_tag]?.rect != null;
      _sourceRect =
          null; // measure the laid-out return tile, including rotation
      _initialRatio =
          _destinations[_tag]?.rect?.size.aspectRatio ?? _initialRatio;
    }
    _tick();
    if (status == AnimationStatus.dismissed) _detach();
  }

  void _tick() {
    if (_disposed) return;
    // Only the active source changes visibility, twice per flight. Never
    // rebuild all mounted photo tiles on every animation tick.
    final hidden = isFlying ? _source?.hidden : null;
    if (!identical(hidden, _hiddenSource)) {
      _hiddenSource?.value = false;
      _hiddenSource = hidden;
      hidden?.value = true;
    }
    final opacity =
        isFlying || (_local && _animation?.status == AnimationStatus.completed)
        ? _fade!.value
        : 0.0;
    chromeOpacity.value = 1 - opacity;
    notifyListeners();
  }

  void _detach() {
    _animation?.removeListener(_tick);
    _animation?.removeStatusListener(_statusChanged);
    _animation = null;
    _fade?.dispose();
    _fade = null;
    _local = false;
  }

  /// Keep the gallery mounted for layout/back/input. Only its paint is deferred
  /// to the chat layer until the local flight reaches its fullscreen endpoint.
  Widget routeTransition(Animation<double> animation, Widget child) =>
      AnimatedBuilder(
        animation: this,
        child: child,
        builder: (_, child) => FadeTransition(
          opacity: isFlying && identical(animation, _animation)
              ? kAlwaysDismissedAnimation
              : _fade ?? animation,
          child: IgnorePointer(ignoring: isFlying, child: child),
        ),
      );

  /// Also handles removeRoute, which need not run a reverse animation.
  void release(Animation<double> animation) {
    if (_disposed || !identical(animation, _animation)) return;
    _detach();
    _tick();
  }

  BorderRadius get borderRadius => BorderRadius.lerp(
    _source?.radius ?? BorderRadius.zero,
    BorderRadius.zero,
    progress,
  )!;
  _PhotoAnchor? get _source => _sources[_tag];

  Rect _flightRect(Size size) {
    final origin = _bounds(_hostKey)?.topLeft ?? Offset.zero;
    final source = _sourceRect ??= _source?.rect;
    final ratio = _initialRatio;
    final fitted = ratio == null
        ? size
        : applyBoxFit(BoxFit.contain, Size(ratio, 1), size).destination;
    final target =
        _destinations[_tag]?.rect ??
        Alignment.center.inscribe(fitted, Offset.zero & size).shift(origin);
    return Rect.lerp(source ?? target, target, progress)!.shift(-origin);
  }

  @override
  void dispose() {
    _disposed = true;
    _hiddenSource = null;
    _detach();
    chromeOpacity.dispose();
    super.dispose();
  }
}

/// Must be after the timeline and before all chat chrome in the same viewport.
class ChatMediaTransitionLayer extends StatefulWidget {
  const ChatMediaTransitionLayer({super.key});
  @override
  State<ChatMediaTransitionLayer> createState() =>
      _ChatMediaTransitionLayerState();
}

class _ChatMediaTransitionLayerState extends State<ChatMediaTransitionLayer> {
  final _key = GlobalKey();
  ChatMediaLocalFlight? _flight;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final flight = ChatMediaTransitionScope.maybeOf(context)?.localFlight;
    if (!identical(flight, _flight)) {
      _unbind();
      _flight = flight;
    }
    flight?._hostKey = _key;
  }

  void _unbind() {
    if (identical(_flight?._hostKey, _key)) _flight?._hostKey = null;
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flight = _flight;
    return IgnorePointer(
      child: SizedBox.expand(
        key: _key,
        child: flight == null
            ? const SizedBox()
            : AnimatedBuilder(
                animation: flight,
                builder: (_, _) {
                  final source = flight._source;
                  if (!flight.isFlying || source == null) {
                    return const SizedBox();
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: 1 - flight.chromeOpacity.value,
                          ),
                        ),
                      ),
                      ChatMediaFlightPhoto(
                        flight: flight,
                        child: ColoredBox(
                          color: Colors.black,
                          child: ChatMediaImage(
                            path: source.path,
                            fit: BoxFit.cover,
                            cacheWidth: source.cacheWidth,
                            revealOnLoad: false,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// One continuous image, measured after layout rather than through sibling sizes.
class ChatMediaFlightPhoto extends SingleChildRenderObjectWidget {
  const ChatMediaFlightPhoto({
    super.key,
    required this.flight,
    required super.child,
  });
  final ChatMediaLocalFlight flight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFlightPhoto(flight);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFlightPhoto).flight = flight;
    renderObject.markNeedsLayout();
    renderObject.markNeedsPaint();
  }
}

class _RenderFlightPhoto extends RenderProxyBox {
  _RenderFlightPhoto(this.flight);
  ChatMediaLocalFlight flight;
  final _clip = LayerHandle<ClipRRectLayer>();
  final _transform = LayerHandle<TransformLayer>();
  @override
  void performLayout() {
    size = constraints.biggest;
    final ratio = flight._initialRatio ?? 1;
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(ratio, 1),
      size,
    ).destination;
    child?.layout(BoxConstraints.tight(fitted), parentUsesSize: true);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = flight._source;
    if (source == null || child == null || child!.size.isEmpty) return;
    final rect = flight._flightRect(size);
    if (rect.isEmpty) return;
    final radius = flight.borderRadius;
    final sx = rect.width / child!.size.width;
    final sy = rect.height / child!.size.height;
    final scale = sx > sy ? sx : sy;
    final matrix = Matrix4.translationValues(
      rect.center.dx - child!.size.width * scale / 2,
      rect.center.dy - child!.size.height * scale / 2,
      0,
    )..scaleByDouble(scale, scale, 1, 1);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      rect,
      radius.toRRect(rect),
      (context, offset) {
        _transform.layer = context.pushTransform(
          needsCompositing,
          offset,
          matrix,
          super.paint,
          oldLayer: _transform.layer,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _transform.layer = null;
    super.dispose();
  }
}
