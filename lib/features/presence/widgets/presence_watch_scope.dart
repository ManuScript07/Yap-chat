import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

/// Registers a bounded, route-lifetime presence audience without coupling the
/// page's business cubit to Realtime lifecycle details.
class PresenceWatchScope extends StatefulWidget {
  const PresenceWatchScope({
    super.key,
    required this.scopeName,
    required this.userIds,
    required this.child,
  });

  final String scopeName;
  final Iterable<String> userIds;
  final Widget child;

  @override
  State<PresenceWatchScope> createState() => _PresenceWatchScopeState();
}

class _PresenceWatchScopeState extends State<PresenceWatchScope> {
  late final String _scopeId =
      '${widget.scopeName}:${identityHashCode(this).toRadixString(16)}';
  IPresenceRepository? _repository;
  Set<String> _lastIds = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??= context.read<IPresenceRepository?>();
    _update();
  }

  @override
  void didUpdateWidget(covariant PresenceWatchScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final ids = widget.userIds.where((id) => id.isNotEmpty).toSet();
    if (_lastIds.length == ids.length && _lastIds.containsAll(ids)) return;
    _lastIds = Set.unmodifiable(ids);
    unawaited(_repository?.setWatchScope(_scopeId, _lastIds));
  }

  @override
  void dispose() {
    unawaited(_repository?.removeWatchScope(_scopeId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
