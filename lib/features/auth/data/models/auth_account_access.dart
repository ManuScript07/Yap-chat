import 'package:equatable/equatable.dart';

/// Result of the narrow account-access check performed by AuthGate.
///
/// The deletion deadline is exposed only to its owner, so an offline client can
/// accurately hide an already-expired recovery action. It never weakens the
/// server-side deadline check.
class AuthAccountAccess extends Equatable {
  const AuthAccountAccess({
    required this.isBanned,
    this.isDeletionPending = false,
    this.isDeletionExpired = false,
    this.deletionScheduledFor,
    this.username,
    this.supportEmail,
  });

  final bool isBanned;
  final bool isDeletionPending;
  final bool isDeletionExpired;
  final DateTime? deletionScheduledFor;
  final String? username;
  final String? supportEmail;

  @override
  List<Object?> get props => [
    isBanned,
    isDeletionPending,
    isDeletionExpired,
    deletionScheduledFor,
    username,
    supportEmail,
  ];
}
