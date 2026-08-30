import 'package:equatable/equatable.dart';

enum DistanceUnit { meters, kilometers }

class UserDistance extends Equatable {
  const UserDistance({
    required this.value,
    required this.unit,
    required this.updatedAt,
  });

  final int value;
  final DistanceUnit unit;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [value, unit, updatedAt];
}
