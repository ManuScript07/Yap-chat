import 'dart:async';

import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Owns foreground location refreshes for the whole application.
///
/// The repository performs silent permission checks and movement filtering;
/// this coordinator only binds refreshes to authentication and app lifecycle.
class LocationTrackingCoordinator {
  LocationTrackingCoordinator({
    required ILocationRepository locationRepository,
    required Talker talker,
    this.refreshInterval = const Duration(minutes: 10),
  }) : _locationRepository = locationRepository,
       _talker = talker;

  final ILocationRepository _locationRepository;
  final Talker _talker;
  final Duration refreshInterval;

  Timer? _timer;
  Future<void>? _activeRefresh;
  Future<TrackedLocationRefreshResult>? _activeInteractiveRefresh;
  String? _activeRefreshUserId;
  String? _userId;
  bool _isForeground = true;
  bool _isDisposed = false;

  Future<void> setAuthenticatedUser(String? userId) async {
    if (_isDisposed || _userId == userId) return;
    _userId = userId;
    _restartTimer();
    if (userId != null && _isForeground) {
      await _refresh(forcePublish: true);
    }
  }

  Future<void> setForeground(bool isForeground) async {
    if (_isDisposed || _isForeground == isForeground) return;
    _isForeground = isForeground;
    _restartTimer();
    if (isForeground && _userId != null) await _refresh();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    await _activeRefresh;
    await _activeInteractiveRefresh;
  }

  /// Serializes an explicit foreground request with background tracking.
  /// It is the only path allowed to show an OS permission prompt, while the
  /// periodic contour remains silent.
  Future<TrackedLocationRefreshResult> refreshWithPermission() {
    final active = _activeInteractiveRefresh;
    if (active != null) return active;
    final userId = _userId;
    if (_isDisposed || userId == null || !_isForeground) {
      return Future.value(TrackedLocationRefreshResult.unavailable);
    }
    final refresh = _performInteractiveRefresh(userId);
    _activeInteractiveRefresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_activeInteractiveRefresh, refresh)) {
        _activeInteractiveRefresh = null;
      }
    });
  }

  Future<TrackedLocationRefreshResult> _performInteractiveRefresh(
    String userId,
  ) async {
    // A silent refresh may already have collected a position. Finish it
    // first; the interactive call then sees its updated local timestamp and
    // avoids a duplicate server write whenever possible.
    await _activeRefresh;
    final result = await _locationRepository.refreshTrackedLocationWithPermission(
      userId,
    );
    _talker.info('Interactive location refresh completed: ${result.name}');
    return result;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_isDisposed || !_isForeground || _userId == null) return;
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(_refresh()));
  }

  Future<void> _refresh({bool forcePublish = false}) {
    final activeRefresh = _activeRefresh;
    final userId = _userId;
    if (_isDisposed || !_isForeground || userId == null) {
      return Future<void>.value();
    }
    if (activeRefresh != null) {
      if (_activeRefreshUserId == userId) return activeRefresh;
      return activeRefresh.then(
        (_) => _refresh(forcePublish: forcePublish),
      );
    }

    final refresh = _performRefresh(userId, forcePublish: forcePublish);
    _activeRefresh = refresh;
    _activeRefreshUserId = userId;
    return refresh.whenComplete(() {
      if (identical(_activeRefresh, refresh)) {
        _activeRefresh = null;
        _activeRefreshUserId = null;
      }
    });
  }

  Future<void> _performRefresh(
    String userId, {
    required bool forcePublish,
  }) async {
    try {
      final result = await _locationRepository.refreshTrackedLocation(
        userId,
        forcePublish: forcePublish,
      );
      _talker.info(
        'Location refresh completed: ${result.name}; '
        'forcePublish=$forcePublish',
      );
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Location refresh failed');
    }
  }
}
