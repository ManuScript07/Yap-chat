import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

/// Maintains one server-side app session and consumes selective presence
/// events from the shared user channel.
class PresenceRepository
    implements IPresenceRepository, IPresenceWatchRepository {
  PresenceRepository({
    required SupabaseClient client,
    required Talker talker,
    UserRealtimeDataSource? userRealtime,
    PresenceStatusStore? statusStore,
    Uuid uuid = const Uuid(),
  }) : _client = client,
       _talker = talker,
       _userRealtime =
           userRealtime ??
           UserRealtimeDataSource(client: client, talker: talker),
       _statusStore = statusStore ?? PresenceStatusStore(),
       _uuid = uuid;

  static const _heartbeatInterval = Duration(seconds: 30);
  static const _sessionLease = Duration(seconds: 75);
  static const _requestTimeout = Duration(seconds: 8);
  static const _maximumScopeSize = 100;

  final SupabaseClient _client;
  final Talker _talker;
  final UserRealtimeDataSource _userRealtime;
  final PresenceStatusStore _statusStore;
  final Uuid _uuid;
  final Map<String, Set<String>> _watchScopes = {};
  final Map<String, Future<bool>> _scopeSyncs = {};
  final Set<String> _dirtyScopes = {};

  StreamSubscription<UserPresenceRealtimeEvent>? _eventSubscription;
  Timer? _heartbeatTimer;
  Future<void> _operation = Future<void>.value();
  String? _connectedUserId;
  String? _scopeOwnerUserId;
  String? _sessionId;
  DateTime? _lastHeartbeatSucceededAt;
  bool _sessionConfirmed = false;
  bool _shouldBeConnected = false;

  @override
  Stream<Set<String>> watchOnlineUserIds() => _statusStore.watch();

  @override
  Future<void> connect(String userId) {
    _shouldBeConnected = true;
    return _serialize(() => _connect(userId));
  }

  Future<void> _connect(String userId) async {
    if (!_shouldBeConnected) return;
    if (_connectedUserId == userId && _sessionId != null) return;
    await _disconnect(closeRemoteSession: true, clearScopes: false);
    if (!_shouldBeConnected) return;

    if (_scopeOwnerUserId != null && _scopeOwnerUserId != userId) {
      _watchScopes.clear();
      _dirtyScopes.clear();
      _statusStore.clear();
    }
    _scopeOwnerUserId = userId;

    _connectedUserId = userId;
    _sessionId = _uuid.v4();
    _dirtyScopes.addAll(_watchScopes.keys);
    _eventSubscription = _userRealtime.watchPresenceEvents().listen(
      (event) => _statusStore.record(event.userId, isOnline: event.isOnline),
      onError: (Object error, StackTrace stackTrace) =>
          _talker.handle(error, stackTrace, 'Presence events failed'),
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
    return _serialize(
      () => _disconnect(closeRemoteSession: true, clearScopes: false),
    );
  }

  Future<void> _disconnect({
    required bool closeRemoteSession,
    required bool clearScopes,
  }) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await subscription?.cancel();

    final sessionId = _sessionId;
    _sessionId = null;
    _sessionConfirmed = false;
    _lastHeartbeatSucceededAt = null;
    _connectedUserId = null;
    if (closeRemoteSession && sessionId != null) {
      try {
        await _client
            .rpc<void>(
              'close_my_presence_session',
              params: {'target_session_id': sessionId},
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // The server lease expires automatically after an abrupt disconnect.
      }
    }
    if (clearScopes) _watchScopes.clear();
    _statusStore.clear();
  }

  Future<void> _heartbeat() async {
    final sessionId = _sessionId;
    final userId = _connectedUserId;
    if (!_shouldBeConnected || sessionId == null || userId == null) return;
    try {
      await _client
          .rpc<void>(
            'touch_my_presence_session',
            params: {'target_session_id': sessionId},
          )
          .timeout(_requestTimeout);
      final mustRestoreScopes = !_sessionConfirmed;
      _sessionConfirmed = true;
      _lastHeartbeatSucceededAt = DateTime.now().toUtc();
      if (mustRestoreScopes) _dirtyScopes.addAll(_watchScopes.keys);
      if (_dirtyScopes.isNotEmpty) {
        await Future.wait(Set<String>.of(_dirtyScopes).map(_synchronizeScope));
      }
    } catch (error, stackTrace) {
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
    _dirtyScopes.add(normalizedScope);
    await _synchronizeScope(normalizedScope);
  }

  @override
  Future<void> removeWatchScope(String scopeId) async {
    final normalizedScope = scopeId.trim();
    if (!_watchScopes.containsKey(normalizedScope)) return;
    _watchScopes.remove(normalizedScope);
    _dirtyScopes.add(normalizedScope);
    await _synchronizeScope(normalizedScope);
  }

  Future<void> _synchronizeScope(String scopeId) async {
    final active = _scopeSyncs[scopeId];
    if (active != null) {
      await active;
      return;
    }
    final sessionId = _sessionId;
    if (!_shouldBeConnected || sessionId == null || !_sessionConfirmed) return;
    final snapshot = Set<String>.of(_watchScopes[scopeId] ?? const {});
    final operation = _performScopeSync(scopeId, sessionId, snapshot);
    _scopeSyncs[scopeId] = operation;
    var succeeded = false;
    try {
      succeeded = await operation;
    } finally {
      if (identical(_scopeSyncs[scopeId], operation)) {
        _scopeSyncs.remove(scopeId);
      }
    }
    if (!_sameSet(_watchScopes[scopeId] ?? const {}, snapshot)) {
      await _synchronizeScope(scopeId);
    } else if (succeeded) {
      _dirtyScopes.remove(scopeId);
    }
  }

  Future<bool> _performScopeSync(
    String scopeId,
    String sessionId,
    Set<String> userIds,
  ) async {
    try {
      final response = await _client
          .rpc<List<dynamic>>(
            'set_my_presence_watch_scope',
            params: {
              'target_session_id': sessionId,
              'scope_key': scopeId,
              'target_user_ids': userIds.toList(growable: false),
            },
          )
          .timeout(_requestTimeout);
      if (_sessionId != sessionId) return false;
      _statusStore.recordAll({
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
