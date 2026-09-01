import 'package:equatable/equatable.dart';

class BlockedUser extends Equatable {
  const BlockedUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.blockedAt,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final DateTime blockedAt;

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    blockedAt,
  ];
}
