import 'dart:async';

/// In-memory online snapshot shared by repositories that already receive
/// presence data in their normal server responses.
///
/// Online state is deliberately not persisted: after a process restart an old
/// `true` would be more misleading than an unknown/offline value.
class PresenceStatusStore {
  final _controller = StreamController<Set<String>>.broadcast();
  Set<String> _onlineUserIds = const {};

  Set<String> get onlineUserIds => _onlineUserIds;

  Stream<Set<String>> watch() async* {
    yield _onlineUserIds;
    yield* _controller.stream;
  }

  void record(String userId, {required bool isOnline}) {
    if (userId.isEmpty) return;
    final next = Set<String>.of(_onlineUserIds);
    final changed = isOnline ? next.add(userId) : next.remove(userId);
    if (!changed) return;
    _emit(next);
  }

  void recordAll(Map<String, bool> statuses) {
    if (statuses.isEmpty) return;
    final next = Set<String>.of(_onlineUserIds);
    var changed = false;
    for (final entry in statuses.entries) {
      if (entry.key.isEmpty) continue;
      changed |= entry.value ? next.add(entry.key) : next.remove(entry.key);
    }
    if (changed) _emit(next);
  }

  void clear() {
    if (_onlineUserIds.isEmpty) return;
    _onlineUserIds = const {};
    if (!_controller.isClosed) _controller.add(_onlineUserIds);
  }

  Future<void> dispose() => _controller.close();

  void _emit(Set<String> value) {
    _onlineUserIds = Set.unmodifiable(value);
    if (!_controller.isClosed) _controller.add(_onlineUserIds);
  }
}
