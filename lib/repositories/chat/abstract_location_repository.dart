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

abstract interface class ILocationRepository {
  Future<Position> getCurrentPosition();

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

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();
}
