import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  test('refreshes on authentication and foreground resume', () async {
    final repository = _FakeLocationRepository();
    final coordinator = LocationTrackingCoordinator(
      locationRepository: repository,
      talker: Talker(),
    );

    await coordinator.setAuthenticatedUser('user-1');
    await coordinator.setAuthenticatedUser('user-1');
    expect(repository.refreshedUserIds, ['user-1']);
    expect(repository.forcePublishValues, [isTrue]);

    await coordinator.setForeground(false);
    await coordinator.setForeground(true);
    expect(repository.refreshedUserIds, ['user-1', 'user-1']);
    expect(repository.forcePublishValues, [isTrue, isFalse]);

    await coordinator.dispose();
  });

  test('does not refresh while signed out or in background', () async {
    final repository = _FakeLocationRepository();
    final coordinator = LocationTrackingCoordinator(
      locationRepository: repository,
      talker: Talker(),
    );

    await coordinator.setForeground(false);
    await coordinator.setAuthenticatedUser('user-1');
    expect(repository.refreshedUserIds, isEmpty);

    await coordinator.setAuthenticatedUser(null);
    await coordinator.setForeground(true);
    expect(repository.refreshedUserIds, isEmpty);

    await coordinator.dispose();
  });

  test(
    'silently refreshes the active account without forcing a publish',
    () async {
      final repository = _FakeLocationRepository();
      final coordinator = LocationTrackingCoordinator(
        locationRepository: repository,
        talker: Talker(),
      );

      await coordinator.setAuthenticatedUser('user-1');
      final result = await coordinator.refreshSilently();

      expect(result, TrackedLocationRefreshResult.updated);
      expect(repository.refreshedUserIds, ['user-1', 'user-1']);
      expect(repository.forcePublishValues, [isTrue, isFalse]);

      await coordinator.dispose();
    },
  );

  test('does not access device location while signed out', () async {
    final repository = _FakeLocationRepository();
    final coordinator = LocationTrackingCoordinator(
      locationRepository: repository,
      talker: Talker(),
    );

    final result = await coordinator.refreshSilently();

    expect(result, TrackedLocationRefreshResult.unavailable);
    expect(repository.refreshedUserIds, isEmpty);

    await coordinator.dispose();
  });
}

class _FakeLocationRepository implements ILocationRepository {
  final List<String> refreshedUserIds = [];
  final List<bool> forcePublishValues = [];

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId, {
    bool forcePublish = false,
  }) async {
    refreshedUserIds.add(userId);
    forcePublishValues.add(forcePublish);
    return TrackedLocationRefreshResult.updated;
  }

  @override
  Future<Position> getCurrentPosition() => throw UnimplementedError();

  @override
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async => null;

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocationWithPermission(
    String userId, {
    bool forcePublish = false,
  }) => refreshTrackedLocation(userId, forcePublish: forcePublish);

  @override
  Future<LocationAccessStatus> getLocationAccessStatus() async =>
      LocationAccessStatus.granted;

  @override
  Future<LocationAccessStatus> requestLocationAccess() async =>
      LocationAccessStatus.granted;

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}
