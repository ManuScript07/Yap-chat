import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';

typedef LocationPositionGetter =
    Future<Position> Function(LocationSettings settings);
typedef LocationPublisher =
    Future<bool> Function(double latitude, double longitude);

class LocationRepository implements ILocationRepository {
  LocationRepository({
    required SharedPreferences preferences,
    SupabaseClient? client,
    Future<bool> Function()? isLocationServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    LocationPositionGetter? getPosition,
    LocationPublisher? publishLocation,
    String? Function()? currentUserId,
    double Function(double, double, double, double)? distanceBetween,
    Duration locationPublishTimeout = defaultLocationPublishTimeout,
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
       _currentUserId = currentUserId ?? (() => client?.auth.currentUser?.id),
       _distanceBetween = distanceBetween ?? Geolocator.distanceBetween,
       _locationPublishTimeout = locationPublishTimeout;

  static const minimumMovementMeters = 100.0;
  static const maximumUnchangedAge = Duration(hours: 12);
  static const _trackedLocationTimeout = Duration(seconds: 20);
  static const defaultLocationPublishTimeout = Duration(seconds: 10);

  final SharedPreferences _preferences;
  final SupabaseClient? _client;
  final Future<bool> Function() _isLocationServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final LocationPositionGetter _getPosition;
  final LocationPublisher? _publishLocation;
  final String? Function() _currentUserId;
  final double Function(double, double, double, double) _distanceBetween;
  final Duration _locationPublishTimeout;

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
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) return null;

    final latitude = _preferences.getDouble(_latitudeKey(userId));
    final longitude = _preferences.getDouble(_longitudeKey(userId));
    final updatedAt = DateTime.tryParse(
      _preferences.getString(_publishedAtKey(userId)) ?? '',
    );
    if (latitude == null || longitude == null || updatedAt == null) return null;

    final age = DateTime.now().toUtc().difference(updatedAt.toUtc());
    if (age.isNegative || age >= maxAge) return null;
    return CachedTrackedLocation(
      latitude: latitude,
      longitude: longitude,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<LocationAccessStatus> getLocationAccessStatus() async {
    if (!await _isLocationServiceEnabled()) {
      return LocationAccessStatus.serviceDisabled;
    }
    return _mapPermission(await _checkPermission());
  }

  @override
  Future<LocationAccessStatus> requestLocationAccess() async {
    if (!await _isLocationServiceEnabled()) {
      return LocationAccessStatus.serviceDisabled;
    }
    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    return _mapPermission(permission);
  }

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId, {
    bool forcePublish = false,
  }) async {
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

    if (!forcePublish && !_shouldPublish(normalizedUserId, position)) {
      return TrackedLocationRefreshResult.unchanged;
    }

    if (_publishLocation == null &&
        (client == null || client.auth.currentUser?.id != normalizedUserId)) {
      return TrackedLocationRefreshResult.unavailable;
    }

    final published = await _publishWithTimeout(
      position.latitude,
      position.longitude,
    );
    if (published == null) return TrackedLocationRefreshResult.unavailable;
    if (!published) return TrackedLocationRefreshResult.unchanged;
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

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocationWithPermission(
    String userId, {
    bool forcePublish = false,
  }) async {
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
    if (!forcePublish && !_shouldPublish(normalizedUserId, position)) {
      return TrackedLocationRefreshResult.unchanged;
    }

    final published = await _publishWithTimeout(
      position.latitude,
      position.longitude,
    );
    if (published == null) return TrackedLocationRefreshResult.unavailable;
    if (!published) return TrackedLocationRefreshResult.unchanged;
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

  Future<bool> _publish(double latitude, double longitude) {
    final publisher = _publishLocation;
    if (publisher != null) return publisher(latitude, longitude);
    return _client!.rpc<bool>(
      'update_my_location_with_result',
      params: {'new_latitude': latitude, 'new_longitude': longitude},
    );
  }

  Future<bool?> _publishWithTimeout(double latitude, double longitude) async {
    try {
      return await _publish(
        latitude,
        longitude,
      ).timeout(_locationPublishTimeout);
    } on TimeoutException {
      return null;
    }
  }

  String _latitudeKey(String userId) => 'tracked_location.$userId.latitude';

  String _longitudeKey(String userId) => 'tracked_location.$userId.longitude';

  String _publishedAtKey(String userId) =>
      'tracked_location.$userId.published_at';

  LocationAccessStatus _mapPermission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.whileInUse ||
        LocationPermission.always => LocationAccessStatus.granted,
        LocationPermission.deniedForever =>
          LocationAccessStatus.permanentlyDenied,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationAccessStatus.denied,
      };

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
