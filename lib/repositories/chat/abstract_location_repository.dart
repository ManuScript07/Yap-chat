import 'package:geolocator/geolocator.dart';

class LocationServiceDisabledFailure implements Exception {}

class LocationPermissionDeniedFailure implements Exception {}

class LocationPermissionPermanentlyDeniedFailure implements Exception {}

enum TrackedLocationRefreshResult { updated, unchanged, unavailable }

abstract interface class ILocationRepository {
  Future<Position> getCurrentPosition();

  /// Silently refreshes the signed-in user's shared location.
  ///
  /// This never requests a permission or opens system UI. If location access
  /// is unavailable, the refresh is skipped.
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(String userId);

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();
}
