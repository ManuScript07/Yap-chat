import 'package:geolocator/geolocator.dart';

class LocationServiceDisabledFailure implements Exception {}

class LocationPermissionDeniedFailure implements Exception {}

class LocationPermissionPermanentlyDeniedFailure implements Exception {}

enum TrackedLocationRefreshResult { updated, unchanged, unavailable }

enum LocationAccessStatus {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
}

/// The last position successfully published for the signed-in account.
///
/// It is deliberately separate from a live [Position]: using it must never
/// wake the device GPS just to render a cached distance.
class CachedTrackedLocation {
  const CachedTrackedLocation({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime updatedAt;
}

abstract interface class ILocationRepository {
  Future<Position> getCurrentPosition();

  /// Returns the current account's last published location from local storage.
  /// A stale record is represented by `null`.
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  });

  /// Reads the current service and permission state without showing OS UI.
  Future<LocationAccessStatus> getLocationAccessStatus();

  /// Requests location permission only while the OS still allows prompting.
  Future<LocationAccessStatus> requestLocationAccess();

  /// Silently refreshes the signed-in user's shared location.
  ///
  /// This never requests a permission or opens system UI. If location access
  /// is unavailable, the refresh is skipped.
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId, {
    bool forcePublish = false,
  });

  /// Requests OS permission if necessary, then refreshes the tracked location.
  /// Background callers must continue to use [refreshTrackedLocation].
  Future<TrackedLocationRefreshResult> refreshTrackedLocationWithPermission(
    String userId, {
    bool forcePublish = false,
  });

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();
}
