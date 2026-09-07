import 'package:drift/drift.dart';
import 'package:yap_chat/core/database/database.dart';

Future<T> measureRpc<T>(
  AppDiagnostics? diagnostics,
  String name,
  Future<T> Function() action,
) => diagnostics?.measureRpc(name, action) ?? action();

/// In-memory, opt-in diagnostics for profiling the application locally.
///
/// It intentionally keeps aggregate counters only: RPC names and durations,
/// but never request parameters, user identifiers, message content or payloads.
class AppDiagnostics {
  AppDiagnostics({required this.enabled});

  final bool enabled;
  final Map<String, _OperationAccumulator> _rpc = {};
  final Map<String, _OperationAccumulator> _sync = {};
  final Map<String, int> _activeRealtimeChannels = {};
  final Map<String, int> _activeLocalListeners = {};
  final _OutboxAccumulator _outbox = _OutboxAccumulator();
  var _presenceEventCount = 0;
  var _presencePayloadBytes = 0;
  var _presenceLargestPayloadBytes = 0;
  CacheDiagnosticsSnapshot? _cache;

  Future<T> measureRpc<T>(String name, Future<T> Function() action) async {
    if (!enabled) return action();
    return _measure(_rpc, name, action);
  }

  Future<T> measureSync<T>(String name, Future<T> Function() action) async {
    if (!enabled) return action();
    return _measure(_sync, name, action);
  }

  void recordSyncItems(String name, int count) {
    if (!enabled || count <= 0) return;
    (_sync[name] ??= _OperationAccumulator()).items += count;
  }

  DiagnosticsLease trackRealtimeChannel(String owner) =>
      _track(_activeRealtimeChannels, owner);

  DiagnosticsLease trackLocalListener(String owner) =>
      _track(_activeLocalListeners, owner);

  void recordPresenceEvent({required int payloadBytes}) {
    if (!enabled) return;
    _presenceEventCount++;
    final normalizedBytes = payloadBytes < 0 ? 0 : payloadBytes;
    _presencePayloadBytes += normalizedBytes;
    if (normalizedBytes > _presenceLargestPayloadBytes) {
      _presenceLargestPayloadBytes = normalizedBytes;
    }
  }

  void recordOutboxAttempt({required bool manual}) {
    if (!enabled) return;
    _outbox.attempts++;
    if (manual) _outbox.manualRetries++;
  }

  void recordOutboxRetry() {
    if (enabled) _outbox.scheduledRetries++;
  }

  void recordOutboxSuccess() {
    if (enabled) _outbox.successes++;
  }

  void recordOutboxError({required bool terminal}) {
    if (!enabled) return;
    _outbox.errors++;
    if (terminal) _outbox.terminalErrors++;
  }

  /// Queries SQLite only when explicitly requested by a developer. It never
  /// runs on a timer or as part of normal synchronization.
  Future<CacheDiagnosticsSnapshot> refreshCacheSnapshot(
    AppDatabase database, {
    String? ownerUserId,
  }) async {
    final messages = await _countRows(
      database,
      table: 'cached_messages',
      ownerUserId: ownerUserId,
    );
    final pending = await _countRows(
      database,
      table: 'pending_chat_operations',
      ownerUserId: ownerUserId,
    );
    final pageCountRow = await database
        .customSelect('PRAGMA page_count')
        .getSingle();
    final pageSizeRow = await database
        .customSelect('PRAGMA page_size')
        .getSingle();
    final pageCount = pageCountRow.read<int>('page_count');
    final pageSize = pageSizeRow.read<int>('page_size');
    final snapshot = CacheDiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      cachedMessageCount: messages,
      pendingOperationCount: pending,
      sqliteBytes: pageCount * pageSize,
    );
    if (enabled) _cache = snapshot;
    return snapshot;
  }

  AppDiagnosticsSnapshot snapshot() => AppDiagnosticsSnapshot(
    capturedAt: DateTime.now().toUtc(),
    enabled: enabled,
    rpc: _snapshotOperations(_rpc),
    sync: _snapshotOperations(_sync),
    activeRealtimeChannels: _snapshotCounts(_activeRealtimeChannels),
    activeLocalListeners: _snapshotCounts(_activeLocalListeners),
    presence: PresenceDiagnosticsSnapshot(
      eventCount: _presenceEventCount,
      totalPayloadBytes: _presencePayloadBytes,
      largestPayloadBytes: _presenceLargestPayloadBytes,
    ),
    outbox: _outbox.snapshot(),
    cache: _cache,
  );

  void reset() {
    if (!enabled) return;
    _rpc.clear();
    _sync.clear();
    _presenceEventCount = 0;
    _presencePayloadBytes = 0;
    _presenceLargestPayloadBytes = 0;
    _outbox.reset();
    _cache = null;
  }

  Future<T> _measure<T>(
    Map<String, _OperationAccumulator> target,
    String name,
    Future<T> Function() action,
  ) async {
    final accumulator = target[name] ??= _OperationAccumulator();
    final watch = Stopwatch()..start();
    accumulator.calls++;
    try {
      return await action();
    } catch (_) {
      accumulator.errors++;
      rethrow;
    } finally {
      watch.stop();
      accumulator.totalMicroseconds += watch.elapsedMicroseconds;
      if (watch.elapsedMicroseconds > accumulator.maxMicroseconds) {
        accumulator.maxMicroseconds = watch.elapsedMicroseconds;
      }
    }
  }

  DiagnosticsLease _track(Map<String, int> target, String owner) {
    if (!enabled) return DiagnosticsLease._noop();
    target.update(owner, (count) => count + 1, ifAbsent: () => 1);
    return DiagnosticsLease._(() {
      final count = target[owner];
      if (count == null || count <= 1) {
        target.remove(owner);
      } else {
        target[owner] = count - 1;
      }
    });
  }

  Future<int> _countRows(
    AppDatabase database, {
    required String table,
    required String? ownerUserId,
  }) async {
    final hasOwner = ownerUserId != null && ownerUserId.isNotEmpty;
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS row_count FROM $table'
          '${hasOwner ? ' WHERE owner_user_id = ?' : ''}',
          variables: hasOwner ? [Variable.withString(ownerUserId)] : const [],
        )
        .getSingle();
    return row.read<int>('row_count');
  }

  Map<String, OperationDiagnosticsSnapshot> _snapshotOperations(
    Map<String, _OperationAccumulator> source,
  ) => Map.unmodifiable({
    for (final entry in source.entries) entry.key: entry.value.snapshot(),
  });

  Map<String, int> _snapshotCounts(Map<String, int> source) =>
      Map.unmodifiable(Map<String, int>.from(source));
}

class DiagnosticsLease {
  DiagnosticsLease._(this._release);
  DiagnosticsLease._noop() : _release = null;

  final void Function()? _release;
  bool _released = false;

  void dispose() {
    if (_released) return;
    _released = true;
    _release?.call();
  }
}

class AppDiagnosticsSnapshot {
  const AppDiagnosticsSnapshot({
    required this.capturedAt,
    required this.enabled,
    required this.rpc,
    required this.sync,
    required this.activeRealtimeChannels,
    required this.activeLocalListeners,
    required this.presence,
    required this.outbox,
    required this.cache,
  });

  final DateTime capturedAt;
  final bool enabled;
  final Map<String, OperationDiagnosticsSnapshot> rpc;
  final Map<String, OperationDiagnosticsSnapshot> sync;
  final Map<String, int> activeRealtimeChannels;
  final Map<String, int> activeLocalListeners;
  final PresenceDiagnosticsSnapshot presence;
  final OutboxDiagnosticsSnapshot outbox;
  final CacheDiagnosticsSnapshot? cache;

  Map<String, Object?> toJson() => {
    'captured_at': capturedAt.toIso8601String(),
    'enabled': enabled,
    // Supabase SDK multiplexes logical channels over its own transport. This
    // is deliberately not presented as a numeric WebSocket count.
    'supabase_client_instances': enabled ? 1 : 0,
    'physical_realtime_transport': 'sdk_managed_not_counted',
    'rpc': {for (final entry in rpc.entries) entry.key: entry.value.toJson()},
    'sync': {for (final entry in sync.entries) entry.key: entry.value.toJson()},
    'active_realtime_channels': activeRealtimeChannels,
    'active_local_listeners': activeLocalListeners,
    'presence': presence.toJson(),
    'outbox': outbox.toJson(),
    'cache': cache?.toJson(),
  };
}

class OperationDiagnosticsSnapshot {
  const OperationDiagnosticsSnapshot({
    required this.calls,
    required this.errors,
    required this.items,
    required this.totalMicroseconds,
    required this.maxMicroseconds,
  });

  final int calls;
  final int errors;
  final int items;
  final int totalMicroseconds;
  final int maxMicroseconds;

  double get averageMilliseconds => calls == 0
      ? 0
      : totalMicroseconds / calls / Duration.microsecondsPerMillisecond;

  Map<String, Object> toJson() => {
    'calls': calls,
    'errors': errors,
    'items': items,
    'total_microseconds': totalMicroseconds,
    'max_microseconds': maxMicroseconds,
    'average_milliseconds': averageMilliseconds,
  };
}

class PresenceDiagnosticsSnapshot {
  const PresenceDiagnosticsSnapshot({
    required this.eventCount,
    required this.totalPayloadBytes,
    required this.largestPayloadBytes,
  });

  final int eventCount;
  final int totalPayloadBytes;
  final int largestPayloadBytes;

  Map<String, int> toJson() => {
    'event_count': eventCount,
    'total_payload_bytes': totalPayloadBytes,
    'largest_payload_bytes': largestPayloadBytes,
  };
}

class OutboxDiagnosticsSnapshot {
  const OutboxDiagnosticsSnapshot({
    required this.attempts,
    required this.manualRetries,
    required this.scheduledRetries,
    required this.successes,
    required this.errors,
    required this.terminalErrors,
  });

  final int attempts;
  final int manualRetries;
  final int scheduledRetries;
  final int successes;
  final int errors;
  final int terminalErrors;

  Map<String, int> toJson() => {
    'attempts': attempts,
    'manual_retries': manualRetries,
    'scheduled_retries': scheduledRetries,
    'successes': successes,
    'errors': errors,
    'terminal_errors': terminalErrors,
  };
}

class CacheDiagnosticsSnapshot {
  const CacheDiagnosticsSnapshot({
    required this.capturedAt,
    required this.cachedMessageCount,
    required this.pendingOperationCount,
    required this.sqliteBytes,
  });

  final DateTime capturedAt;
  final int cachedMessageCount;
  final int pendingOperationCount;
  final int sqliteBytes;

  Map<String, Object> toJson() => {
    'captured_at': capturedAt.toIso8601String(),
    'cached_message_count': cachedMessageCount,
    'pending_operation_count': pendingOperationCount,
    'sqlite_bytes': sqliteBytes,
  };
}

class _OperationAccumulator {
  var calls = 0;
  var errors = 0;
  var items = 0;
  var totalMicroseconds = 0;
  var maxMicroseconds = 0;

  OperationDiagnosticsSnapshot snapshot() => OperationDiagnosticsSnapshot(
    calls: calls,
    errors: errors,
    items: items,
    totalMicroseconds: totalMicroseconds,
    maxMicroseconds: maxMicroseconds,
  );
}

class _OutboxAccumulator {
  var attempts = 0;
  var manualRetries = 0;
  var scheduledRetries = 0;
  var successes = 0;
  var errors = 0;
  var terminalErrors = 0;

  OutboxDiagnosticsSnapshot snapshot() => OutboxDiagnosticsSnapshot(
    attempts: attempts,
    manualRetries: manualRetries,
    scheduledRetries: scheduledRetries,
    successes: successes,
    errors: errors,
    terminalErrors: terminalErrors,
  );

  void reset() {
    attempts = 0;
    manualRetries = 0;
    scheduledRetries = 0;
    successes = 0;
    errors = 0;
    terminalErrors = 0;
  }
}
