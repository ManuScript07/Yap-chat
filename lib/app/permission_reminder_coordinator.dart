import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/repositories.dart';

enum PermissionReminderKind {
  notificationsBlocked,
  locationPermission,
  locationPermissionPermanentlyDenied,
  locationServiceDisabled,
}

typedef ReminderThresholdPicker = int Function(int min, int max);

/// Counts authenticated cold starts and selects at most one permission prompt
/// for the current app process. Counters are isolated by user and permission.
class PermissionReminderCoordinator {
  PermissionReminderCoordinator({
    required SharedPreferences preferences,
    required IPushNotificationsRepository notificationsRepository,
    required ILocationRepository locationRepository,
    required Talker talker,
    ReminderThresholdPicker? thresholdPicker,
  }) : _preferences = preferences,
       _notificationsRepository = notificationsRepository,
       _locationRepository = locationRepository,
       _talker = talker,
       _thresholdPicker = thresholdPicker ?? _randomThreshold;

  static final Random _random = Random.secure();

  final SharedPreferences _preferences;
  final IPushNotificationsRepository _notificationsRepository;
  final ILocationRepository _locationRepository;
  final Talker _talker;
  final ReminderThresholdPicker _thresholdPicker;
  bool _launchEvaluated = false;

  Future<PermissionReminderKind?> reminderForLaunch(String userId) async {
    final normalizedUserId = userId.trim();
    if (_launchEvaluated || normalizedUserId.isEmpty) return null;
    _launchEvaluated = true;

    try {
      final results = await Future.wait<Object>([
        _notificationsRepository.getPermissionStatus(),
        _locationRepository.getLocationAccessStatus(),
      ]);
      final notificationStatus = results[0] as PushPermissionStatus;
      final locationStatus = results[1] as LocationAccessStatus;

      final notificationDue = await _advanceCounter(
        normalizedUserId,
        _ReminderCounter.notifications,
        active: notificationStatus == PushPermissionStatus.denied,
      );
      final locationServiceDue = await _advanceCounter(
        normalizedUserId,
        _ReminderCounter.locationService,
        active: locationStatus == LocationAccessStatus.serviceDisabled,
      );
      final locationPermissionDue = await _advanceCounter(
        normalizedUserId,
        _ReminderCounter.locationPermission,
        active:
            locationStatus == LocationAccessStatus.denied ||
            locationStatus == LocationAccessStatus.permanentlyDenied,
      );

      if (notificationDue) {
        return PermissionReminderKind.notificationsBlocked;
      }
      if (locationServiceDue) {
        return PermissionReminderKind.locationServiceDisabled;
      }
      if (locationPermissionDue) {
        return locationStatus == LocationAccessStatus.permanentlyDenied
            ? PermissionReminderKind.locationPermissionPermanentlyDenied
            : PermissionReminderKind.locationPermission;
      }
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Permission reminder check failed');
    }
    return null;
  }

  Future<void> markPresented(String userId, PermissionReminderKind kind) async {
    final counter = switch (kind) {
      PermissionReminderKind.notificationsBlocked =>
        _ReminderCounter.notifications,
      PermissionReminderKind.locationPermission ||
      PermissionReminderKind.locationPermissionPermanentlyDenied =>
        _ReminderCounter.locationPermission,
      PermissionReminderKind.locationServiceDisabled =>
        _ReminderCounter.locationService,
    };
    await Future.wait([
      _preferences.setInt(_countKey(userId, counter), 0),
      _preferences.setInt(
        _thresholdKey(userId, counter),
        _pickThreshold(counter),
      ),
    ]);
  }

  Future<bool> _advanceCounter(
    String userId,
    _ReminderCounter counter, {
    required bool active,
  }) async {
    final countKey = _countKey(userId, counter);
    final thresholdKey = _thresholdKey(userId, counter);
    if (!active) {
      await Future.wait([
        _preferences.remove(countKey),
        _preferences.remove(thresholdKey),
      ]);
      return false;
    }

    var threshold = _preferences.getInt(thresholdKey);
    if (threshold == null) {
      threshold = _pickThreshold(counter);
      await _preferences.setInt(thresholdKey, threshold);
    }
    final count = (_preferences.getInt(countKey) ?? 0) + 1;
    await _preferences.setInt(countKey, count);
    return count >= threshold;
  }

  int _pickThreshold(_ReminderCounter counter) => switch (counter) {
    _ReminderCounter.notifications ||
    _ReminderCounter.locationPermission => _thresholdPicker(6, 8),
    _ReminderCounter.locationService => _thresholdPicker(4, 5),
  };

  String _countKey(String userId, _ReminderCounter counter) =>
      'permission_reminder.$userId.${counter.name}.count';

  String _thresholdKey(String userId, _ReminderCounter counter) =>
      'permission_reminder.$userId.${counter.name}.threshold';

  static int _randomThreshold(int min, int max) =>
      min + _random.nextInt(max - min + 1);
}

enum _ReminderCounter { notifications, locationPermission, locationService }
