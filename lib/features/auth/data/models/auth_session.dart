import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({
    required this.userId,
    this.email,
    this.displayName,
    this.birthDate,
    this.avatarUrl,
  });

  final String userId;
  final String? email;
  final String? displayName;
  final DateTime? birthDate;
  final String? avatarUrl;

  @override
  List<Object?> get props => [userId, email, displayName, birthDate, avatarUrl];
}
