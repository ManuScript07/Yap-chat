import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/permission_reminder_coordinator.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shows a blocked-notification reminder on every sixth launch', () async {
    final preferences = await SharedPreferences.getInstance();
    final notifications = _ReminderNotificationsRepository(
      PushPermissionStatus.denied,
    );
    final location = _ReminderLocationRepository(LocationAccessStatus.granted);

    for (var launch = 1; launch <= 5; launch++) {
      expect(
        await _coordinator(
          preferences,
          notifications,
          location,
        ).reminderForLaunch('user'),
        isNull,
      );
    }
    final sixth = _coordinator(preferences, notifications, location);
    expect(
      await sixth.reminderForLaunch('user'),
      PermissionReminderKind.notificationsBlocked,
    );
    await sixth.markPresented(
      'user',
      PermissionReminderKind.notificationsBlocked,
    );

    for (var launch = 1; launch <= 5; launch++) {
      expect(
        await _coordinator(
          preferences,
          notifications,
          location,
        ).reminderForLaunch('user'),
        isNull,
      );
    }
    expect(
      await _coordinator(
        preferences,
        notifications,
        location,
      ).reminderForLaunch('user'),
      PermissionReminderKind.notificationsBlocked,
    );
  });

  test(
    'reminds about a disabled location service on the fourth launch',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final notifications = _ReminderNotificationsRepository(
        PushPermissionStatus.authorized,
      );
      final location = _ReminderLocationRepository(
        LocationAccessStatus.serviceDisabled,
      );

      for (var launch = 1; launch <= 3; launch++) {
        expect(
          await _coordinator(
            preferences,
            notifications,
            location,
          ).reminderForLaunch('user'),
          isNull,
        );
      }
      expect(
        await _coordinator(
          preferences,
          notifications,
          location,
        ).reminderForLaunch('user'),
        PermissionReminderKind.locationServiceDisabled,
      );
    },
  );

  test('selects only one due reminder and preserves the other', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('permission_reminder.user.notifications.count', 5);
    await preferences.setInt(
      'permission_reminder.user.notifications.threshold',
      6,
    );
    await preferences.setInt(
      'permission_reminder.user.locationPermission.count',
      5,
    );
    await preferences.setInt(
      'permission_reminder.user.locationPermission.threshold',
      6,
    );
    final notifications = _ReminderNotificationsRepository(
      PushPermissionStatus.denied,
    );
    final location = _ReminderLocationRepository(
      LocationAccessStatus.permanentlyDenied,
    );

    final first = _coordinator(preferences, notifications, location);
    expect(
      await first.reminderForLaunch('user'),
      PermissionReminderKind.notificationsBlocked,
    );
    expect(await first.reminderForLaunch('user'), isNull);
    await first.markPresented(
      'user',
      PermissionReminderKind.notificationsBlocked,
    );

    expect(
      await _coordinator(
        preferences,
        notifications,
        location,
      ).reminderForLaunch('user'),
      PermissionReminderKind.locationPermissionPermanentlyDenied,
    );
  });

  test('clears a counter after permission is granted', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('permission_reminder.user.notifications.count', 5);
    await preferences.setInt(
      'permission_reminder.user.notifications.threshold',
      6,
    );

    expect(
      await _coordinator(
        preferences,
        _ReminderNotificationsRepository(PushPermissionStatus.authorized),
        _ReminderLocationRepository(LocationAccessStatus.granted),
      ).reminderForLaunch('user'),
      isNull,
    );
    expect(
      preferences.getInt('permission_reminder.user.notifications.count'),
      isNull,
    );
  });
}

PermissionReminderCoordinator _coordinator(
  SharedPreferences preferences,
  IPushNotificationsRepository notifications,
  ILocationRepository location,
) => PermissionReminderCoordinator(
  preferences: preferences,
  notificationsRepository: notifications,
  locationRepository: location,
  talker: Talker(),
  thresholdPicker: (min, max) => min,
);

class _ReminderNotificationsRepository implements IPushNotificationsRepository {
  _ReminderNotificationsRepository(this.status);

  final PushPermissionStatus status;

  @override
  Stream<String> get openedConversationIds => const Stream.empty();

  @override
  Stream<String> get openedProfileIds => const Stream.empty();

  @override
  Future<PushPermissionStatus> getPermissionStatus() async => status;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> setActiveConversation(String? conversationId) async {}

  @override
  Future<void> setAppForeground(bool isForeground) async {}

  @override
  Future<void> setAuthenticatedUser(String? userId) async {}

  @override
  Future<void> unregisterCurrentDevice() async {}

  @override
  Future<void> cancelAll() async {}
}

class _ReminderLocationRepository implements ILocationRepository {
  _ReminderLocationRepository(this.status);

  final LocationAccessStatus status;

  @override
  Future<LocationAccessStatus> getLocationAccessStatus() async => status;

  @override
  Future<LocationAccessStatus> requestLocationAccess() async => status;

  @override
  Future<Position> getCurrentPosition() => throw UnimplementedError();

  @override
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async => null;

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId, {
    bool forcePublish = false,
  }) async => TrackedLocationRefreshResult.unavailable;

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocationWithPermission(
    String userId, {
    bool forcePublish = false,
  }) async => TrackedLocationRefreshResult.unavailable;
}
