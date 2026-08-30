import 'package:equatable/equatable.dart';

enum FriendLocationAvailability { current, hidden, unavailable }

class FriendLocation extends Equatable {
  const FriendLocation({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [latitude, longitude, updatedAt];
}

/// The server can deliberately withhold fresh coordinates while a previously
/// cached point remains usable offline.  Keeping that distinction explicit
/// prevents privacy changes from being mistaken for a missing location.
class FriendLocationLookup extends Equatable {
  const FriendLocationLookup({required this.availability, this.location})
    : assert(
        (availability == FriendLocationAvailability.current) ==
            (location != null),
      );

  const FriendLocationLookup.current(FriendLocation location)
    : this(
        availability: FriendLocationAvailability.current,
        location: location,
      );

  const FriendLocationLookup.hidden()
    : this(availability: FriendLocationAvailability.hidden);

  const FriendLocationLookup.unavailable()
    : this(availability: FriendLocationAvailability.unavailable);

  final FriendLocationAvailability availability;
  final FriendLocation? location;

  @override
  List<Object?> get props => [availability, location];
}
