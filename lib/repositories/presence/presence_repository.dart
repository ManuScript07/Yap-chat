import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';
import 'package:yap_chat/repositories/presence/presence_snapshot.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

/// Maintains one server-side app session and consumes selective presence
/// events from the shared user channel.
class PresenceRepository
    implements
        IPresenceRepository,
        IPresenceWatchRepository,
        IPresenceLifecycleRepository {
  PresenceRepository({
    required SupabaseClient client,
    required Talker talker,
    UserRealtimeDataSource? userRealtime,
    PresenceStatusStore? statusStore,
    AppDiagnostics? diagnostics,
    Uuid uuid = const Uuid(),
  }) : _client = client,
       _talker = talker,
       _userRealtime =
           userRealtime ??
           UserRealtimeDataSource(client: client, talker: talker),
       _statusStore = statusStore ?? PresenceStatusStore(),
       _diagnostics = diagnostics,
       _uuid = uuid;

  static const _heartbeatInterval = Duration(seconds: 30);
  static const _sessionLease = Duration(seconds: 75);
  static const _requestTimeout = Duration(seconds: 8);
  static const _maximumScopeSize = 100;

  final SupabaseClient _client;
  final Talker _talker;
  final UserRealtimeDataSource _userRealtime;
  final PresenceStatusStore _statusStore;
  final AppDiagnostics? _diagnostics;
  final Uuid _uuid;
  final Map<String, Set<String>> _watchScopes = {};
  final Map<String, Future<bool>> _scopeSyncs = {};
  final Map<String, int> _scopeRevisions = {};
  final Set<String> _dirtyScopes = {};

  StreamSubscription<UserPresenceRealtimeEvent>? _eventSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  DiagnosticsLease? _eventListenerLease;
  Timer? _heartbeatTimer;
  Future<void> _operation = Future<void>.value();
  String? _connectedUserId;
  String? _scopeOwnerUserId;
  String? _sessionId;
  DateTime? _lastHeartbeatSucceededAt;
  bool _sessionConfirmed = false;
  bool _shouldBeConnected = false;

  @override
  Stream<Set<String>> watchOnlineUserIds() {
    return _watchStore(_statusStore.watch());
  }

  @override
  Stream<PresenceSnapshot> watchPresenceSnapshots() =>
      _watchStore(_statusStore.watchSnapshots());

  Stream<T> _watchStore<T>(Stream<T> stream) {
    return Stream.multi((controller) {
      final lease = _diagnostics?.trackLocalListener('presence-status-store');
      final subscription = stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await subscription.cancel();
        lease?.dispose();
      };
    });
  }

  @override
  Future<void> connect(String userId) {
    _shouldBeConnected = true;
    return _serialize(() => _connect(userId));
  }

  Future<void> _connect(String userId) async {
    if (!_shouldBeConnected) return;
    if (_connectedUserId == userId && _sessionId != null) return;
    if (_sessionId != null) {
      await _disconnect(clearScopes: false);
    }
    if (!_shouldBeConnected) return;

    if (_scopeOwnerUserId != null && _scopeOwnerUserId != userId) {
      _watchScopes.clear();
      _dirtyScopes.clear();
      _scopeRevisions.clear();
      _statusStore.clear();
    }
    _scopeOwnerUserId = userId;

    _connectedUserId = userId;
    _sessionId = _uuid.v4();
    final sessionId = _sessionId!;
    _markAllScopesDirty();
    _statusStore.beginRevalidation(_requestTimeout * 2);
    _connectionSubscription = _userRealtime.watchConnectionEvents().listen((
      joined,
    ) {
      if (!_isCurrent(sessionId)) return;
      if (!joined) {
        _statusStore.beginRevalidation(_requestTimeout * 2, restart: false);
        return;
      }
      // Catch changes missed before joining or during SDK rejoin. Reuse the
      // existing session and coalesced scope RPCs, never create another channel.
      _markAllScopesDirty();
      unawaited(_synchronizeDirtyScopes());
    });
    _eventSubscription = _userRealtime.watchPresenceEvents().listen(
      (event) {
        if (_isCurrent(sessionId) &&
            (event.viewerUserId == null || event.viewerUserId == userId)) {
          _statusStore.record(event.userId, isOnline: event.isOnline);
        }
      },
      onError: (Object error, StackTrace stackTrace) =>
          _talker.handle(error, stackTrace, 'Presence events failed'),
    );
    _eventListenerLease = _diagnostics?.trackLocalListener(
      'presence-realtime-events',
    );
    await _userRealtime.resume();
    await _heartbeat();
    if (!_shouldBeConnected || _connectedUserId != userId) return;
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_heartbeat()),
    );
  }

  @override
  Future<void> disconnect() {
    _shouldBeConnected = false;
    _statusStore.clear();
    return _serialize(() => _disconnect(clearScopes: true));
  }

  @override
  Future<void> suspend() {
    _shouldBeConnected = false;
    _statusStore.suspend();
    return _serialize(() => _disconnect(clearScopes: false));
  }

  Future<void> _disconnect({required bool clearScopes}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await subscription?.cancel();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _eventListenerLease?.dispose();
    _eventListenerLease = null;

    final sessionId = _sessionId;
    _sessionId = null;
    _sessionConfirmed = false;
    _lastHeartbeatSucceededAt = null;
    _connectedUserId = null;
    // An old session's request must not suppress a new session's synchronization.
    _scopeSyncs.clear();
    if (clearScopes) {
      _scopeOwnerUserId = null;
      _watchScopes.clear();
      _dirtyScopes.clear();
      _scopeRevisions.clear();
    }
    if (sessionId != null) {
      try {
        await measureRpc(
          _diagnostics,
          'close_my_presence_session',
          () => _client
              .rpc<void>(
                'close_my_presence_session',
                params: {'target_session_id': sessionId},
              )
              .retry(enabled: false)
              .timeout(const Duration(seconds: 3)),
        );
      } catch (_) {
        // The server lease expires automatically after an abrupt disconnect.
      }
    }
  }

  Future<void> _heartbeat() async {
    final sessionId = _sessionId;
    final userId = _connectedUserId;
    if (!_shouldBeConnected || sessionId == null || userId == null) return;
    try {
      await measureRpc(
        _diagnostics,
        'touch_my_presence_session',
        () => _client
            .rpc<void>(
              'touch_my_presence_session',
              params: {'target_session_id': sessionId},
            )
            // This repository already retries via its single heartbeat timer.
            // Disable hidden SDK retries so one attempt sends one request;
            // the repository owns the retry schedule and timeout.
            .retry(enabled: false)
            .timeout(_requestTimeout),
      );
      if (!_isCurrent(sessionId)) return;
      final mustRestoreScopes = !_sessionConfirmed;
      _sessionConfirmed = true;
      _lastHeartbeatSucceededAt = DateTime.now().toUtc();
      if (mustRestoreScopes) _markAllScopesDirty();
      await _synchronizeDirtyScopes();
    } catch (error, stackTrace) {
      if (!_isCurrent(sessionId)) return;
      final lastSuccess = _lastHeartbeatSucceededAt;
      if (lastSuccess == null ||
          DateTime.now().toUtc().difference(lastSuccess) >= _sessionLease) {
        _sessionConfirmed = false;
      }
      _talker.handle(error, stackTrace, 'Presence heartbeat failed');
    }
  }

  @override
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds) async {
    final normalizedScope = scopeId.trim();
    if (normalizedScope.isEmpty) return;
    final normalizedIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != _connectedUserId)
        .toSet();
    if (normalizedIds.length > _maximumScopeSize) {
      throw ArgumentError.value(
        normalizedIds.length,
        'userIds',
        'A presence watch scope supports at most $_maximumScopeSize users',
      );
    }
    if (_sameSet(_watchScopes[normalizedScope], normalizedIds)) return;
    _watchScopes[normalizedScope] = Set.unmodifiable(normalizedIds);
    _markScopeDirty(normalizedScope);
    await _synchronizeScope(normalizedScope);
  }

  @override
  Future<void> removeWatchScope(String scopeId) async {
    final normalizedScope = scopeId.trim();
    if (!_watchScopes.containsKey(normalizedScope)) return;
    _watchScopes.remove(normalizedScope);
    _markScopeDirty(normalizedScope);
    await _synchronizeScope(normalizedScope);
  }

  Future<void> _synchronizeScope(String scopeId) async {
    final active = _scopeSyncs[scopeId];
    if (active != null) {
      final succeeded = await active;
      if (succeeded && _dirtyScopes.contains(scopeId)) {
        await _synchronizeScope(scopeId);
      }
      return;
    }
    final sessionId = _sessionId;
    if (!_shouldBeConnected || sessionId == null || !_sessionConfirmed) return;
    final operation = _synchronizeScopeLoop(scopeId, sessionId);
    _scopeSyncs[scopeId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_scopeSyncs[scopeId], operation)) {
        _scopeSyncs.remove(scopeId);
      }
    }
  }

  Future<bool> _synchronizeScopeLoop(String scopeId, String sessionId) async {
    while (_isCurrent(sessionId) && _sessionConfirmed) {
      final revision = _scopeRevisions[scopeId];
      final ids = Set<String>.of(_watchScopes[scopeId] ?? const {});
      final succeeded = await _performScopeSync(
        scopeId,
        sessionId,
        ids,
        revision,
      );
      if (!_isCurrent(sessionId) || !succeeded) return false;
      if (_scopeRevisions[scopeId] == revision) {
        _dirtyScopes.remove(scopeId);
        if (!_watchScopes.containsKey(scopeId)) _scopeRevisions.remove(scopeId);
        return true;
      }
    }
    return false;
  }

  bool _isCurrent(String sessionId) =>
      _shouldBeConnected && _sessionId == sessionId;

  void _markScopeDirty(String scopeId) {
    _dirtyScopes.add(scopeId);
    _scopeRevisions[scopeId] = (_scopeRevisions[scopeId] ?? 0) + 1;
  }

  void _markAllScopesDirty() {
    for (final scopeId in _watchScopes.keys) {
      _markScopeDirty(scopeId);
    }
  }

  Future<void> _synchronizeDirtyScopes() async {
    await Future.wait(Set<String>.of(_dirtyScopes).map(_synchronizeScope));
  }

  Future<bool> _performScopeSync(
    String scopeId,
    String sessionId,
    Set<String> userIds,
    int? revision,
  ) async {
    final ticket = _statusStore.captureSnapshot();
    try {
      final response = await measureRpc(
        _diagnostics,
        'set_my_presence_watch_scope',
        () => _client
            .rpc<List<dynamic>>(
              'set_my_presence_watch_scope',
              params: {
                'target_session_id': sessionId,
                'scope_key': scopeId,
                'target_user_ids': userIds.toList(growable: false),
              },
            )
            .retry(enabled: false)
            .timeout(_requestTimeout),
      );
      if (!_isCurrent(sessionId)) return false;
      if (_scopeRevisions[scopeId] != revision) return true;
      _statusStore.applySnapshot(ticket, {
        for (final item in response)
          if (item is Map &&
              item['target_user_id'] is String &&
              item['is_online'] is bool)
            item['target_user_id'] as String: item['is_online'] as bool,
      });
      return true;
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Presence audience sync failed');
      return false;
    }
  }

  bool _sameSet(Set<String>? first, Set<String> second) =>
      first != null &&
      first.length == second.length &&
      first.containsAll(second);

  Future<void> _serialize(Future<void> Function() action) {
    final next = _operation.then((_) => action(), onError: (_) => action());
    _operation = next;
    return next;
  }
}
