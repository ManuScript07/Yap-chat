import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum NavigationScrollTarget { chats, nearby, friends }

/// UI commands scoped to MainPage; does not own data, queries or subscriptions.
class NavigationScrollToTopController {
  final _targets =
      <NavigationScrollTarget, _NavigationScrollToTopTargetState>{};

  Future<void> scrollToTop(NavigationScrollTarget target) =>
      _targets[target]?._scrollToTop() ?? Future<void>.value();

  void cancel() {
    for (final target in _targets.values.toList()) {
      target._cancel();
    }
  }

  void dispose() => _targets.clear();
}

class NavigationScrollToTopTarget extends StatefulWidget {
  const NavigationScrollToTopTarget({
    super.key,
    required this.target,
    required this.controller,
    required this.child,
    this.enabled = true,
    this.onActivityChanged,
  });

  final NavigationScrollTarget target;
  final ScrollController controller;
  final Widget child;
  final bool enabled;
  final ValueChanged<bool>? onActivityChanged;

  @override
  State<NavigationScrollToTopTarget> createState() =>
      _NavigationScrollToTopTargetState();
}

class _NavigationScrollToTopTargetState
    extends State<NavigationScrollToTopTarget> {
  NavigationScrollToTopController? _owner;
  ScrollController? _activeController;
  bool _busy = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.read<NavigationScrollToTopController?>();
    if (!identical(owner, _owner)) {
      _unregister();
      _owner = owner;
      owner?._targets[widget.target] = this;
    }
  }

  @override
  void didUpdateWidget(covariant NavigationScrollToTopTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || !widget.enabled) _cancel();
    if (oldWidget.target != widget.target) {
      if (identical(_owner?._targets[oldWidget.target], this)) {
        _owner?._targets.remove(oldWidget.target);
      }
      _owner?._targets[widget.target] = this;
    }
  }

  void _unregister() {
    if (identical(_owner?._targets[widget.target], this)) {
      _owner?._targets.remove(widget.target);
    }
  }

  Future<void> _scrollToTop() async {
    final controller = widget.controller;
    if (!mounted ||
        !widget.enabled ||
        _busy ||
        !controller.hasClients ||
        controller.positions.length != 1) {
      return;
    }
    final position = controller.position;
    final destination = position.minScrollExtent;
    final distance = position.pixels - destination;
    if (distance <= .5) return;
    final generation = ++_generation;
    _busy = true;
    _activeController = controller;
    widget.onActivityChanged?.call(true);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpTo(destination);
      } else {
        await controller.animateTo(
          destination,
          duration: Duration(
            milliseconds: (280 + distance / 10).clamp(360, 650).round(),
          ),
          curve: Curves.easeInOutCubic,
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        _busy = false;
        _activeController = null;
        widget.onActivityChanged?.call(false);
      }
    }
  }

  void _cancel({bool stopPosition = true}) {
    if (!_busy) return;
    final controller = _activeController;
    _generation++;
    _busy = false;
    _activeController = null;
    try {
      // Stopping a driven activity emits scroll notifications as well. Keep
      // pagination suppressed until those synchronous notifications finish.
      if (stopPosition && controller != null && controller.hasClients) {
        for (final position in controller.positions.toList()) {
          position.jumpTo(position.pixels);
        }
      }
    } finally {
      widget.onActivityChanged?.call(false);
    }
  }

  @override
  void dispose() {
    _unregister();
    _cancel(stopPosition: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
