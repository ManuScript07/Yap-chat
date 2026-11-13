import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('silent refresh does not request a denied permission', () async {
    final preferences = await SharedPreferences.getInstance();
    var permissionRequests = 0;
    var publishes = 0;
    final repository = LocationRepository(
      preferences: preferences,
      isLocationServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        permissionRequests++;
        return LocationPermission.whileInUse;
      },
      getPosition: (_) async => _position(55, 37),
      publishLocation: (_, _) async {
        publishes++;
        return true;
      },
    );

    final result = await repository.refreshTrackedLocation('user-1');

    expect(result, TrackedLocationRefreshResult.unavailable);
    expect(permissionRequests, 0);
    expect(publishes, 0);
  });

  test('reads permission state without opening an OS prompt', () async {
    final preferences = await SharedPreferences.getInstance();
    var permissionRequests = 0;
    final repository = LocationRepository(
      preferences: preferences,
      isLocationServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async {
        permissionRequests++;
        return LocationPermission.whileInUse;
      },
    );

    expect(
      await repository.getLocationAccessStatus(),
      LocationAccessStatus.denied,
    );
    expect(permissionRequests, 0);
  });

  test(
    'requests location permission only when it is still requestable',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var permissionRequests = 0;
      final repository = LocationRepository(
        preferences: preferences,
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          permissionRequests++;
          return LocationPermission.whileInUse;
        },
      );

      expect(
        await repository.requestLocationAccess(),
        LocationAccessStatus.granted,
      );
      expect(permissionRequests, 1);
    },
  );

  test('publishes and remembers the first tracked location', () async {
    final preferences = await SharedPreferences.getInstance();
    final published = <(double, double)>[];
    final repository = _repository(
      preferences,
      position: _position(55, 37),
      onPublish: (latitude, longitude) async {
        published.add((latitude, longitude));
        return true;
      },
    );

    final result = await repository.refreshTrackedLocation('user-1');

    expect(result, TrackedLocationRefreshResult.updated);
    expect(published, [(55, 37)]);
    expect(preferences.getDouble('tracked_location.user-1.latitude'), 55);
    expect(preferences.getDouble('tracked_location.user-1.longitude'), 37);
  });

  test(
    'reads a recent locally published location without accessing GPS',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final publishedAt = DateTime.now().toUtc().subtract(
        const Duration(hours: 2),
      );
      await _remember(
        preferences,
        latitude: 55,
        longitude: 37,
        publishedAt: publishedAt,
      );
      final repository = LocationRepository(
        preferences: preferences,
        currentUserId: () => 'user-1',
      );

      final cached = await repository.getCachedCurrentLocation();

      expect(cached?.latitude, 55);
      expect(cached?.longitude, 37);
      expect(cached?.updatedAt.toUtc(), publishedAt);
    },
  );

  test(
    'does not use a locally published location older than 24 hours',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await _remember(
        preferences,
        latitude: 55,
        longitude: 37,
        publishedAt: DateTime.now().toUtc().subtract(const Duration(hours: 24)),
      );
      final repository = LocationRepository(
        preferences: preferences,
        currentUserId: () => 'user-1',
      );

      expect(await repository.getCachedCurrentLocation(), isNull);
    },
  );

  test('skips a fresh location below the movement threshold', () async {
    final preferences = await SharedPreferences.getInstance();
    await _remember(preferences, latitude: 55, longitude: 37);
    var publishes = 0;
    final repository = _repository(
      preferences,
      position: _position(55.0001, 37.0001),
      distance: 15,
      onPublish: (_, _) async {
        publishes++;
        return true;
      },
    );

    final result = await repository.refreshTrackedLocation('user-1');

    expect(result, TrackedLocationRefreshResult.unchanged);
    expect(publishes, 0);
  });

  test('publishes after noticeable movement', () async {
    final preferences = await SharedPreferences.getInstance();
    await _remember(preferences, latitude: 55, longitude: 37);
    var publishes = 0;
    final repository = _repository(
      preferences,
      position: _position(55.01, 37.01),
      distance: LocationRepository.minimumMovementMeters,
      onPublish: (_, _) async {
        publishes++;
        return true;
      },
    );

    final result = await repository.refreshTrackedLocation('user-1');

    expect(result, TrackedLocationRefreshResult.updated);
    expect(publishes, 1);
  });

  test('forced launch refresh publishes despite unchanged position', () async {
    final preferences = await SharedPreferences.getInstance();
    await _remember(preferences, latitude: 55, longitude: 37);
    var publishes = 0;
    final repository = _repository(
      preferences,
      position: _position(55, 37),
      distance: 0,
      onPublish: (_, _) async {
        publishes++;
        return true;
      },
    );

    final result = await repository.refreshTrackedLocation(
      'user-1',
      forcePublish: true,
    );

    expect(result, TrackedLocationRefreshResult.updated);
    expect(publishes, 1);
  });

  test(
    'refreshes an unchanged location before the server TTL expires',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await _remember(
        preferences,
        latitude: 55,
        longitude: 37,
        publishedAt: DateTime.now().toUtc().subtract(
          LocationRepository.maximumUnchangedAge,
        ),
      );
      var publishes = 0;
      final repository = _repository(
        preferences,
        position: _position(55, 37),
        distance: 0,
        onPublish: (_, _) async {
          publishes++;
          return true;
        },
      );

      final result = await repository.refreshTrackedLocation('user-1');

      expect(result, TrackedLocationRefreshResult.updated);
      expect(publishes, 1);
    },
  );

  test(
    'does not advance the local point when the server rate-limits a write',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await _remember(preferences, latitude: 55, longitude: 37);
      final repository = _repository(
        preferences,
        position: _position(56, 38),
        distance: LocationRepository.minimumMovementMeters,
        onPublish: (_, _) async => false,
      );

      final result = await repository.refreshTrackedLocation('user-1');

      expect(result, TrackedLocationRefreshResult.unchanged);
      expect(preferences.getDouble('tracked_location.user-1.latitude'), 55);
      expect(preferences.getDouble('tracked_location.user-1.longitude'), 37);
    },
  );

  test(
    'remembers the server point when a rate-limited write returns metadata',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final serverUpdatedAt = DateTime.now().toUtc().subtract(
        const Duration(seconds: 30),
      );
      final repository = LocationRepository(
        preferences: preferences,
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        getPosition: (_) async => _position(56, 38),
        publishLocationMetadata: (_, _) async => LocationPublishResult(
          didUpdate: false,
          latitude: 55,
          longitude: 37,
          updatedAt: serverUpdatedAt,
        ),
      );

      final result = await repository.refreshTrackedLocation('user-1');

      expect(result, TrackedLocationRefreshResult.unchanged);
      expect(preferences.getDouble('tracked_location.user-1.latitude'), 55);
      expect(preferences.getDouble('tracked_location.user-1.longitude'), 37);
      expect(
        DateTime.parse(
          preferences.getString('tracked_location.user-1.published_at')!,
        ).toUtc(),
        serverUpdatedAt,
      );
    },
  );

  test('stops waiting for an unavailable location publication', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = _repository(
      preferences,
      position: _position(55, 37),
      onPublish: (_, _) => Completer<bool>().future,
      locationPublishTimeout: Duration.zero,
    );

    final result = await repository.refreshTrackedLocation('user-1');

    expect(result, TrackedLocationRefreshResult.unavailable);
  });
}

LocationRepository _repository(
  SharedPreferences preferences, {
  required Position position,
  required LocationPublisher onPublish,
  double distance = 0,
  Duration locationPublishTimeout =
      LocationRepository.defaultLocationPublishTimeout,
}) {
  return LocationRepository(
    preferences: preferences,
    isLocationServiceEnabled: () async => true,
    checkPermission: () async => LocationPermission.whileInUse,
    getPosition: (_) async => position,
    publishLocation: onPublish,
    distanceBetween: (_, _, _, _) => distance,
    locationPublishTimeout: locationPublishTimeout,
  );
}

Future<void> _remember(
  SharedPreferences preferences, {
  required double latitude,
  required double longitude,
  DateTime? publishedAt,
}) async {
  await preferences.setDouble('tracked_location.user-1.latitude', latitude);
  await preferences.setDouble('tracked_location.user-1.longitude', longitude);
  await preferences.setString(
    'tracked_location.user-1.published_at',
    (publishedAt ?? DateTime.now().toUtc()).toIso8601String(),
  );
}

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.now(),
  altitude: 0,
  altitudeAccuracy: 0,
  accuracy: 10,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
