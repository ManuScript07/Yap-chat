import 'package:equatable/equatable.dart';

class DeviceContactPhone extends Equatable {
  const DeviceContactPhone({
    required this.id,
    required this.displayName,
    required this.normalizedPhone,
  });

  final String id;
  final String displayName;
  final String normalizedPhone;

  @override
  List<Object?> get props => [id, displayName, normalizedPhone];
}
