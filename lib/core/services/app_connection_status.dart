import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_session_controller.dart';
import 'app_diagnostics.dart';

enum _Availability { unknown, connecting, ready, unavailable, rejected, paused }

/// Identity of observed work, never a token or request payload.
class ConnectionObservation {
  const ConnectionObservation._(
    this.session,
    this.lifecycle,
    this.network,
    this.sequence,
  );

  final AccountSessionSnapshot session;
  final int lifecycle, network, sequence;
}

/// Passive, account-scoped presentation state. `true` means "connecting…".
///
/// This class never issues requests, creates channels or initiates recovery.
/// API and Realtime evidence are independent; an HTTP success cannot repair a
/// failed subscription. Existing repositories/SDK remain the recovery owners.
class AppConnectionStatus {
  AppConnectionStatus({
    required AccountSessionController accountSessionController,
    this.presentationDelay = const Duration(milliseconds: 250),
    this.enabled = true,
  }) : _account = accountSessionController {
    synchronizeSession();
  }

  final AccountSessionController _account;
  final Duration presentationDelay;
  final bool enabled;
  final _presentationState = ValueNotifier(false);
  ValueListenable<bool> get listenable => _presentationState;
  bool get value => _presentationState.value;
  void addListener(VoidCallback listener) =>
      _presentationState.addListener(listener);
  void removeListener(VoidCallback listener) =>
      _presentationState.removeListener(listener);
  AccountSessionSnapshot? _session;
  _Availability _api = _Availability.unknown, _realtime = _Availability.unknown;
  bool? _networkAvailable;
  int? _nativeNetworkGeneration;
  bool _visible = true, _suspended = false, _active = true, _disposed = false;
  bool _channelConfirmed = false;
  int _lifecycle = 0, _network = 0, _sequence = 0, _appliedApiSequence = 0;
  int _realtimeStartedAt = 0;
  Timer? _presentation;
  StreamSubscription<RealtimeHeartbeatStatus>? _heartbeats;

  /// Must also run when auth is revoked without a network/lifecycle event.
  void synchronizeSession({bool active = true}) {
    if (_disposed) return;
    final previous = _session;
    final currentId = _account.userId;
    final changed = previous == null
        ? currentId != null
        : !_account.isCurrent(previous);
    if (changed || _active != active) {
      _presentation?.cancel();
      _presentation = null;
      _presentationState.value = false;
      _lifecycle++;
      _api = _Availability.unknown;
      _realtime = _Availability.unknown;
      _channelConfirmed = false;
      _session = currentId == null ? null : _account.capture();
      _appliedApiSequence = 0;
      _realtimeStartedAt = _sequence + 1;
    }
    _active = active;
    _publish();
  }

  /// Short inactive intervals suppress presentation without invalidating work.
  /// Only a true background suspension invalidates old request completions.
  void setForeground(bool visible, {bool suspended = false}) {
    if (_disposed) return;
    synchronizeSession(active: _active);
    if (suspended && !_suspended) {
      _lifecycle++;
      // The coordinator may coalesce a quick pause/resume and retain the
      // channel. Only the channel owner can invalidate its confirmation.
    }
    _visible = visible;
    _suspended = suspended || (_suspended && !visible);
    _publish();
  }

  void reportNetworkAvailability(bool available, {int? generation}) {
    if (_disposed ||
        (_networkAvailable == available &&
            (generation == null || generation == _nativeNetworkGeneration))) {
      return;
    }
    synchronizeSession(active: _active);
    _networkAvailable = available;
    _nativeNetworkGeneration = generation;
    _network++;
    if (!available) {
      _api = _Availability.unknown;
      if (_realtime == _Availability.ready) {
        // A surviving socket needs fresh channel traffic/heartbeat evidence.
        _realtime = _Availability.connecting;
      }
    }
    _publish();
  }

  ConnectionObservation? capture() => _capture(allowSuspended: false);

  /// A channel can survive a UI pause coalesced by the lifecycle coordinator.
  ConnectionObservation? captureRealtime() => _capture(allowSuspended: true);

  ConnectionObservation? _capture({required bool allowSuspended}) {
    if (_disposed) return null;
    synchronizeSession(active: _active);
    final session = _session;
    if (!enabled ||
        !_active ||
        (!allowSuspended && _suspended) ||
        session == null) {
      return null;
    }
    return ConnectionObservation._(session, _lifecycle, _network, ++_sequence);
  }

  bool _current(
    ConnectionObservation? ticket, {
    bool checkNetwork = false,
    bool checkLifecycle = true,
    bool allowSuspended = false,
  }) =>
      !_disposed &&
      _active &&
      (allowSuspended || !_suspended) &&
      ticket != null &&
      _account.isCurrent(ticket.session) &&
      (!checkLifecycle || ticket.lifecycle == _lifecycle) &&
      (!checkNetwork || ticket.network == _network);

  Future<T> observe<T>(Future<T> Function() action) async {
    final ticket = capture();
    try {
      final result = await action();
      _apiResult(ticket, failed: false);
      return result;
    } catch (error) {
      // Aborts and local decoding failures provide no availability evidence.
      if (error is! http.RequestAbortedException &&
          (isConnectionFailure(error) || error is PostgrestException)) {
        _apiResult(ticket, failed: isConnectionFailure(error));
      }
      rethrow;
    }
  }

  void _apiResult(ConnectionObservation? ticket, {required bool failed}) {
    if (!_current(ticket, checkNetwork: true) ||
        ticket!.sequence < _appliedApiSequence ||
        _networkAvailable == false) {
      return;
    }
    _appliedApiSequence = ticket.sequence;
    _api = failed ? _Availability.unavailable : _Availability.ready;
    _publish();
  }

  void realtimeConnecting(ConnectionObservation? ticket) {
    if (!_currentRealtime(ticket)) return;
    _realtimeStartedAt = ticket!.sequence;
    _channelConfirmed = false;
    // The SDK may retry a rejected private join. A known access rejection
    // must not become a network banner for the duration of every retry.
    if (_realtime != _Availability.rejected) {
      _realtime = _Availability.connecting;
    }
    _publish();
  }

  void realtimeSubscribed(ConnectionObservation? ticket) {
    if (!_currentRealtime(ticket) || _networkAvailable == false) return;
    _channelConfirmed = true;
    _realtime = _Availability.ready;
    _publish();
  }

  void realtimeUnavailable(ConnectionObservation? ticket) {
    if (!_currentRealtime(ticket)) return;
    _channelConfirmed = false;
    _realtime = _Availability.unavailable;
    _publish();
  }

  /// A rejected private channel on a live socket is not evidence of network loss.
  void realtimeRejected(ConnectionObservation? ticket) {
    if (!_currentRealtime(ticket)) return;
    _channelConfirmed = false;
    _realtime = _Availability.rejected;
    _publish();
  }

  void realtimePaused() {
    if (_disposed) return;
    _channelConfirmed = false;
    _realtimeStartedAt = _sequence + 1;
    _realtime = _Availability.paused;
    _publish();
  }

  bool _currentRealtime(ConnectionObservation? ticket) =>
      _current(ticket, checkLifecycle: false, allowSuspended: true) &&
      ticket!.sequence >= _realtimeStartedAt;

  /// Observes an existing recovery boundary without initiating any recovery.
  void invalidatePendingRequests() {
    if (_disposed) return;
    _lifecycle++;
  }

  /// Listens to the SDK's existing heartbeat. It neither sends nor accelerates it.
  void watchHeartbeats(Stream<RealtimeHeartbeatStatus> events) {
    if (_disposed || _heartbeats != null) return;
    _heartbeats = events.listen((status) {
      final ticket = capture();
      if (!_current(ticket) ||
          !_channelConfirmed ||
          _networkAvailable == false) {
        return;
      }
      if (status == RealtimeHeartbeatStatus.ok) {
        _realtime = _Availability.ready;
        _publish();
      } else if (status == RealtimeHeartbeatStatus.error) {
        // A negative heartbeat reply does not close the SDK socket or revoke
        // its private-channel subscription. The next ACK can confirm recovery.
        _realtime = _Availability.unavailable;
        _publish();
      } else if (status == RealtimeHeartbeatStatus.timeout) {
        realtimeUnavailable(ticket);
      }
    });
  }

  bool get _needsConnection =>
      enabled &&
      _active &&
      _session != null &&
      _account.isCurrent(_session!) &&
      _visible &&
      !_suspended &&
      (_networkAvailable == false ||
          _api == _Availability.unavailable ||
          _realtime == _Availability.connecting ||
          _realtime == _Availability.unavailable);

  void _publish() {
    if (!_needsConnection) {
      _presentation?.cancel();
      _presentation = null;
      _presentationState.value = false;
    } else if (!value && _presentation == null) {
      if (presentationDelay == Duration.zero) {
        _presentationState.value = true;
      } else {
        _presentation = Timer(presentationDelay, () {
          _presentation = null;
          if (!_disposed) {
            _presentationState.value = _needsConnection;
          }
        });
      }
    }
  }

  static bool isConnectionFailure(Object? error) {
    if (error is http.RequestAbortedException) return false;
    if (error is TimeoutException ||
        error is SocketException ||
        error is TlsException ||
        error is http.ClientException) {
      return true;
    }
    if (error is PostgrestException) {
      return const {
        '502',
        '503',
        '504',
        'PGRST000',
        'PGRST001',
        'PGRST002',
      }.contains(error.code);
    }
    return false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _presentation?.cancel();
    unawaited(_heartbeats?.cancel());
    _presentationState.dispose();
  }
}

/// Production observation is independent of opt-in diagnostic aggregation.
Future<T> observeSupabaseRpc<T>(
  AppConnectionStatus? connection,
  AppDiagnostics? diagnostics,
  String name,
  Future<T> Function() action,
) => measureRpc(
  diagnostics,
  name,
  () => connection?.observe(action) ?? action(),
);
