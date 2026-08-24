import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';

typedef LocationPositionGetter =
    Future<Position> Function(LocationSettings settings);
typedef LocationPublisher =
    Future<void> Function(double latitude, double longitude);

class LocationRepository implements ILocationRepository {
  LocationRepository({
    required SharedPreferences preferences,
    SupabaseClient? client,
    Future<bool> Function()? isLocationServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    LocationPositionGetter? getPosition,
    LocationPublisher? publishLocation,
    double Function(double, double, double, double)? distanceBetween,
  }) : _preferences = preferences,
       _client = client,
       _isLocationServiceEnabled =
           isLocationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _getPosition =
           getPosition ??
           ((settings) =>
               Geolocator.getCurrentPosition(locationSettings: settings)),
       _publishLocation = publishLocation,
       _distanceBetween = distanceBetween ?? Geolocator.distanceBetween;

  static const minimumMovementMeters = 100.0;
  static const maximumUnchangedAge = Duration(hours: 12);
  static const _trackedLocationTimeout = Duration(seconds: 20);

  final SharedPreferences _preferences;
  final SupabaseClient? _client;
  final Future<bool> Function() _isLocationServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final LocationPositionGetter _getPosition;
  final LocationPublisher? _publishLocation;
  final double Function(double, double, double, double) _distanceBetween;

  @override
  Future<Position> getCurrentPosition() async {
    if (!await _isLocationServiceEnabled()) {
      throw LocationServiceDisabledFailure();
    }

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw LocationPermissionDeniedFailure();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionPermanentlyDeniedFailure();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw LocationPermissionDeniedFailure();
    }

    return _getPosition(
      const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId,
  ) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return TrackedLocationRefreshResult.unavailable;
    }

    final client = _client;
    if (_publishLocation == null &&
        (client == null || client.auth.currentUser?.id != normalizedUserId)) {
      return TrackedLocationRefreshResult.unavailable;
    }
    if (!await _isLocationServiceEnabled()) {
      return TrackedLocationRefreshResult.unavailable;
    }

    final permission = await _checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return TrackedLocationRefreshResult.unavailable;
    }

    final Position position;
    try {
      position = await _getPosition(
        const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _trackedLocationTimeout,
        ),
      );
    } on TimeoutException {
      return TrackedLocationRefreshResult.unavailable;
    }

    if (!_shouldPublish(normalizedUserId, position)) {
      return TrackedLocationRefreshResult.unchanged;
    }

    if (_publishLocation == null &&
        (client == null || client.auth.currentUser?.id != normalizedUserId)) {
      return TrackedLocationRefreshResult.unavailable;
    }

    await _publish(position.latitude, position.longitude);
    await Future.wait([
      _preferences.setDouble(_latitudeKey(normalizedUserId), position.latitude),
      _preferences.setDouble(
        _longitudeKey(normalizedUserId),
        position.longitude,
      ),
      _preferences.setString(
        _publishedAtKey(normalizedUserId),
        DateTime.now().toUtc().toIso8601String(),
      ),
    ]);
    return TrackedLocationRefreshResult.updated;
  }

  bool _shouldPublish(String userId, Position position) {
    final latitude = _preferences.getDouble(_latitudeKey(userId));
    final longitude = _preferences.getDouble(_longitudeKey(userId));
    final publishedAt = DateTime.tryParse(
      _preferences.getString(_publishedAtKey(userId)) ?? '',
    );
    if (latitude == null || longitude == null || publishedAt == null) {
      return true;
    }

    final age = DateTime.now().toUtc().difference(publishedAt.toUtc());
    if (age.isNegative || age >= maximumUnchangedAge) return true;

    return _distanceBetween(
          latitude,
          longitude,
          position.latitude,
          position.longitude,
        ) >=
        minimumMovementMeters;
  }

  Future<void> _publish(double latitude, double longitude) {
    final publisher = _publishLocation;
    if (publisher != null) return publisher(latitude, longitude);
    return _client!.rpc<void>(
      'update_my_location',
      params: {'new_latitude': latitude, 'new_longitude': longitude},
    );
  }

  String _latitudeKey(String userId) => 'tracked_location.$userId.latitude';

  String _longitudeKey(String userId) => 'tracked_location.$userId.longitude';

  String _publishedAtKey(String userId) =>
      'tracked_location.$userId.published_at';

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
