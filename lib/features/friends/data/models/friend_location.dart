import 'package:equatable/equatable.dart';

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
