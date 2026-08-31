import 'package:flutter/widgets.dart';

/// Serializes profile opens initiated outside the widget tree (for example,
/// from a push notification) and prevents duplicate routes for the same user.
class ProfileNavigationCoordinator {
  ProfileNavigationCoordinator({
    required Future<void> Function(String userId) navigateToProfile,
    required bool Function(String userId) isProfileVisible,
    required bool Function() isActive,
    required void Function(Object error, StackTrace stackTrace, String message)
    onError,
    Future<void> Function()? waitForFrame,
  }) : _navigateToProfile = navigateToProfile,
       _isProfileVisible = isProfileVisible,
       _isActive = isActive,
       _onError = onError,
       _waitForFrame = waitForFrame ?? _waitForNextFrame;

  final Future<void> Function(String userId) _navigateToProfile;
  final bool Function(String userId) _isProfileVisible;
  final bool Function() _isActive;
  final void Function(Object error, StackTrace stackTrace, String message)
  _onError;
  final Future<void> Function() _waitForFrame;

  Future<void> _queue = Future<void>.value();
  final Set<String> _queuedUserIds = <String>{};

  Future<void> open(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty ||
        _isProfileVisible(normalizedUserId) ||
        !_queuedUserIds.add(normalizedUserId)) {
      return _queue;
    }

    _queue = _queue.then<void>((_) => _openQueuedProfile(normalizedUserId));
    return _queue;
  }

  Future<void> _openQueuedProfile(String userId) async {
    try {
      await _waitForFrame();
      if (!_isActive() || _isProfileVisible(userId)) return;
      await _navigateToProfile(userId);
    } catch (error, stackTrace) {
      _onError(error, stackTrace, 'Profile navigation failed');
    } finally {
      _queuedUserIds.remove(userId);
    }
  }

  static Future<void> _waitForNextFrame() => WidgetsBinding.instance.endOfFrame;
}
