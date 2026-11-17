import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pulls the scrollable down with the gesture and holds space for the ring
/// until the refresh completes.
class PullRefresh extends StatefulWidget {
  const PullRefresh({
    super.key,
    required this.indicatorTop,
    required this.onRefresh,
    required this.child,
    this.refreshing = false,
    this.indicatorKey,
    this.onScroll,
    this.onActivityChanged,
    this.overlayBuilder,
    this.useSliverInset = false,
    this.showExternalProgress = false,
  });

  final double indicatorTop;
  final Future<void> Function() onRefresh;
  final Widget child;
  final bool refreshing;
  final Key? indicatorKey;
  final void Function(ScrollNotification)? onScroll;
  final ValueChanged<bool>? onActivityChanged;
  final Widget Function(bool pullingToRefresh)? overlayBuilder;
  final bool useSliverInset;
  final bool showExternalProgress;

  static const physics = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  State<PullRefresh> createState() => _PullRefreshState();
}

class _PullRefreshState extends State<PullRefresh> {
  static const _refreshTriggerExtent = 42.0;
  static const _refreshRevealStart = 14.0;
  static const _refreshGap = 76.0;
  static const _minimumRefreshIndicatorDuration = Duration(milliseconds: 280);

  bool _isSnapping = false;
  var _pullExtent = 0.0;
  var _isRefreshRunning = false;
  var _isPulling = false;
  var _isArmed = false;
  var _hasArmedHaptic = false;

  bool get _externalProgress =>
      widget.showExternalProgress && widget.refreshing;

  double get _dragProgress => _isArmed || _isSnapping || _externalProgress
      ? 1
      : 1 -
            math.exp(
              -math.max(0.0, _pullExtent - _refreshRevealStart) /
                  (_refreshTriggerExtent - _refreshRevealStart),
            );

  double get _refreshInset => _isRefreshRunning || _isArmed || _isSnapping
      ? _refreshGap
      : _refreshGap * _dragProgress;

  bool get _shouldShowIndicator =>
      _isRefreshRunning || _isSnapping || _dragProgress > 0;

  void _onRefreshStatusChanged(RefreshIndicatorStatus? status) {
    if (!mounted) return;
    if (status == RefreshIndicatorStatus.armed) {
      if (!_hasArmedHaptic) {
        _hasArmedHaptic = true;
        unawaited(HapticFeedback.mediumImpact());
      }
      setState(() => _isArmed = true);
    } else if (status == RefreshIndicatorStatus.snap) {
      setState(() {
        _isSnapping = true;
        _isPulling = false;
        _pullExtent = _refreshTriggerExtent;
      });
    } else if (status == RefreshIndicatorStatus.canceled || status == null) {
      if (!_isRefreshRunning) _resetPull();
    }
  }

  bool _trackPull(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (_isRefreshRunning || _isSnapping || widget.refreshing) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _isPulling =
          notification.dragDetails != null &&
          notification.metrics.extentBefore <= 0;
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      if (!_isPulling &&
          notification is ScrollUpdateNotification &&
          notification.dragDetails != null) {
        _isPulling = notification.metrics.extentBefore <= 0;
      }
      if (_isPulling) {
        if (notification.metrics.pixels >
            notification.metrics.minScrollExtent) {
          _isPulling = false;
          _resetPull();
          return false;
        }
        var pullExtent = math
            .max(
              0.0,
              notification.metrics.minScrollExtent -
                  notification.metrics.pixels,
            )
            .toDouble();
        if (notification is OverscrollNotification &&
            notification.overscroll < 0) {
          pullExtent = math
              .max(pullExtent, _pullExtent - notification.overscroll)
              .toDouble();
        }
        _setPullExtent(pullExtent);
      }
    } else if (notification is ScrollEndNotification && _isPulling) {
      _isPulling = false;
      // The standard indicator alone decides whether releasing starts refresh.
      if (!_isArmed) _resetPull();
    }
    return false;
  }

  void _setPullExtent(double pullExtent) {
    final normalized = math.max(0.0, pullExtent);
    if (_pullExtent != normalized && mounted) {
      setState(() {
        _pullExtent = normalized;
      });
    }
  }

  void _resetPull() {
    if (!mounted) return;
    setState(() {
      _pullExtent = 0;
      _isPulling = false;
      _isArmed = false;
      _isSnapping = false;
      _hasArmedHaptic = false;
    });
  }

  Future<void> _handleRefresh() async {
    if (!mounted || _isRefreshRunning) return;
    final startedAt = DateTime.now();
    widget.onActivityChanged?.call(true);
    if (mounted) {
      setState(() {
        _isRefreshRunning = true;
        _isSnapping = false;
        _isPulling = false;
        _isArmed = false;
        _pullExtent = _refreshTriggerExtent;
      });
    }
    try {
      await widget.onRefresh();
    } finally {
      final remaining =
          _minimumRefreshIndicatorDuration -
          DateTime.now().difference(startedAt);
      if (!remaining.isNegative) await Future<void>.delayed(remaining);
      if (mounted) {
        setState(() {
          _isRefreshRunning = false;
          _isPulling = false;
          _pullExtent = 0;
          _isArmed = false;
          _hasArmedHaptic = false;
        });
      }
      widget.onActivityChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator.noSpinner(
    onStatusChange: _onRefreshStatusChanged,
    onRefresh: _handleRefresh,
    notificationPredicate: (notification) =>
        notification.depth == 0 && (!widget.refreshing || _isRefreshRunning),
    child: TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _refreshInset),
      duration: _isPulling ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          widget.onScroll?.call(notification);
          return _trackPull(notification);
        },
        child: widget.child,
      ),
      builder: (context, inset, child) => Stack(
        children: [
          if (widget.useSliverInset)
            _PullRefreshInset(inset: inset, child: child!)
          else
            Transform.translate(offset: Offset(0, inset), child: child),
          Positioned(
            top: widget.indicatorTop + (inset - 36) / 2,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: PullRefreshIndicator(
                key: widget.indicatorKey,
                opacity: _shouldShowIndicator
                    ? (_isRefreshRunning || _isArmed ? 1 : _dragProgress)
                    : 0,
                progress: _dragProgress,
                spinning: _isRefreshRunning || _externalProgress,
              ),
            ),
          ),
          if (widget.overlayBuilder case final builder?)
            builder(_isRefreshRunning),
        ],
      ),
    ),
  );
}

class _PullRefreshInset extends InheritedWidget {
  const _PullRefreshInset({required this.inset, required super.child});

  final double inset;

  @override
  bool updateShouldNotify(_PullRefreshInset oldWidget) =>
      inset != oldWidget.inset;
}

/// Reserves pull-to-refresh space after a pinned header.
class SliverPullRefreshGap extends StatelessWidget {
  const SliverPullRefreshGap({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(
      height:
          context
              .dependOnInheritedWidgetOfExactType<_PullRefreshInset>()
              ?.inset ??
          0,
    ),
  );
}

/// Retains the current ring while fading out instead of replacing a spinning
/// ring with an empty determinate one in the first dismissal frame.
class PullRefreshIndicator extends StatefulWidget {
  const PullRefreshIndicator({
    super.key,
    required this.opacity,
    required this.progress,
    required this.spinning,
    this.size = 36,
    this.strokeWidth = 4,
  });

  final double opacity;
  final double progress;
  final bool spinning;
  final double size;
  final double strokeWidth;

  @override
  State<PullRefreshIndicator> createState() => PullRefreshIndicatorState();
}

class PullRefreshIndicatorState extends State<PullRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final _visibility = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.opacity,
  );
  late bool _spinning = widget.spinning;

  @override
  void didUpdateWidget(covariant PullRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opacity > 0) _spinning = widget.spinning;
    if (widget.opacity != oldWidget.opacity) {
      _visibility.animateTo(widget.opacity, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _visibility,
    child: Center(
      heightFactor: 1,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: CircularProgressIndicator(
            key: ValueKey(
              _spinning ? 'nearby_refresh_spinner' : 'nearby_refresh_progress',
            ),
            value: _spinning ? null : widget.progress,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    ),
    builder: (context, child) => TickerMode(
      enabled: _visibility.value > 0,
      child: Opacity(
        opacity: _visibility.value,
        child: Transform.scale(
          scale: .85 + .15 * _visibility.value,
          child: child,
        ),
      ),
    ),
  );
}
