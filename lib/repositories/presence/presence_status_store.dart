import 'dart:async';

import 'presence_snapshot.dart';

/// Captured before starting an RPC, never when its response arrives.
class PresenceSnapshotTicket {
  const PresenceSnapshotTicket._(this.epoch, this.order, this.eventClock);
  final int epoch;
  final int order;
  final int eventClock;
}

class _Observation {
  const _Observation(
    this.online,
    this.revision,
    this.eventClock,
    this.order, {
    this.offlineEvent = false,
  });
  final bool? online;
  final int revision;
  final int eventClock;
  final int order;
  final bool offlineEvent;
}

/// Volatile observations shared by existing RPCs and the single user channel.
/// Delayed snapshots cannot undo newer events or cross account boundaries.
class PresenceStatusStore {
  final _controller = StreamController<PresenceSnapshot>.broadcast();
  final Map<String, _Observation> _observations = {};
  PresenceSnapshot _snapshot = const PresenceSnapshot();
  int _epoch = 0;
  int _order = 0;
  int _eventClock = 0;
  int _revision = 0;
  Timer? _revalidationTimer;
  int _revalidationRevision = 0;

  Set<String> get onlineUserIds => _snapshot.onlineUserIds;

  Stream<PresenceSnapshot> watchSnapshots() => Stream.multi((controller) {
    final subscription = _controller.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.add(_snapshot);
    controller.onCancel = subscription.cancel;
  });

  Stream<Set<String>> watch() => watchSnapshots()
      .map((snapshot) => snapshot.onlineUserIds)
      .distinct(_sameSet);

  PresenceSnapshotTicket captureSnapshot() =>
      PresenceSnapshotTicket._(_epoch, ++_order, _eventClock);

  void applySnapshot(
    PresenceSnapshotTicket ticket,
    Map<String, bool> statuses,
  ) {
    if (ticket.epoch != _epoch) return;
    for (final entry in statuses.entries) {
      if (entry.key.isEmpty) continue;
      final previous = _observations[entry.key];
      if (previous != null &&
          (previous.eventClock > ticket.eventClock ||
              previous.order > ticket.order)) {
        continue;
      }
      _observations[entry.key] = _Observation(
        entry.value,
        ++_revision,
        previous?.eventClock ?? 0,
        ticket.order,
      );
    }
    _publish();
  }

  /// Events take precedence even if online membership did not change.
  void record(String userId, {required bool isOnline}) =>
      recordAll({userId: isOnline});

  void recordAll(Map<String, bool> statuses) {
    for (final entry in statuses.entries) {
      if (entry.key.isEmpty) continue;
      _observations[entry.key] = _Observation(
        entry.value,
        ++_revision,
        ++_eventClock,
        _observations[entry.key]?.order ?? 0,
        offlineEvent: !entry.value,
      );
    }
    _publish();
  }

  /// Keep last-known values briefly during recovery, not indefinitely after a
  /// failed connection. Expiry is unknown, not a confirmed peer logout.
  void beginRevalidation(Duration grace, {bool restart = true}) {
    // A later failure must also cover observations refreshed since the first
    // attempt, while keeping the original deadline bounded during retry storms.
    _revalidationRevision = _revision;
    if (!restart && _revalidationTimer != null) return;
    _revalidationTimer?.cancel();
    _revalidationTimer = Timer(grace, () {
      _revalidationTimer = null;
      for (final entry in _observations.entries.toList(growable: false)) {
        final observation = entry.value;
        if (observation.online != true ||
            observation.revision > _revalidationRevision) {
          continue;
        }
        _observations[entry.key] = _Observation(
          null,
          ++_revision,
          ++_eventClock,
          observation.order,
        );
      }
      _publish();
    });
  }

  void suspend() {
    _revalidationTimer?.cancel();
    _revalidationTimer = null;
    // Reject requests from the suspended connection without inventing logout.
    _epoch++;
  }

  void clear() {
    suspend();
    _observations.clear();
    _publish();
  }

  Future<void> dispose() {
    _revalidationTimer?.cancel();
    return _controller.close();
  }

  void _publish() {
    final online = <String>{};
    final offline = <String>{};
    final offlineEvents = <String>{};
    for (final entry in _observations.entries) {
      if (entry.value.online == true) online.add(entry.key);
      if (entry.value.online == false) offline.add(entry.key);
      if (entry.value.offlineEvent) offlineEvents.add(entry.key);
    }
    if (_sameSet(online, _snapshot.onlineUserIds) &&
        _sameSet(offline, _snapshot.confirmedOfflineUserIds) &&
        _sameSet(offlineEvents, _snapshot.offlineEventUserIds)) {
      return;
    }
    _snapshot = PresenceSnapshot(
      onlineUserIds: Set.unmodifiable(online),
      confirmedOfflineUserIds: Set.unmodifiable(offline),
      offlineEventUserIds: Set.unmodifiable(offlineEvents),
    );
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
