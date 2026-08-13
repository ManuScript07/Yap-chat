import 'package:geolocator/geolocator.dart';

class LocationServiceDisabledFailure implements Exception {}

class LocationPermissionDeniedFailure implements Exception {}

class LocationPermissionPermanentlyDeniedFailure implements Exception {}

abstract interface class ILocationRepository {
  Future<Position> getCurrentPosition();

  Future<bool> openLocationSettings();

  Future<bool> openAppSettings();
}
