import 'package:equatable/equatable.dart';

/// Result of the narrow account-access check performed by AuthGate.
///
/// The server deliberately returns no moderation reason or expiry date. The
/// username is sufficient to identify the account on the restricted page even
/// when profile data is no longer available to a globally banned session.
class AuthAccountAccess extends Equatable {
  const AuthAccountAccess({
    required this.isBanned,
    this.username,
    this.supportEmail,
  });

  final bool isBanned;
  final String? username;
  final String? supportEmail;

  @override
  List<Object?> get props => [isBanned, username, supportEmail];
}
