import 'package:equatable/equatable.dart';

class Friend extends Equatable {
  const Friend({
    required this.id,
    required this.username,
    required this.displayName,
    required this.friendsSince,
    this.avatarUrl,
    this.avatarStoragePath,
    this.cachedAvatarPath,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final String? cachedAvatarPath;
  final DateTime friendsSince;

  Friend copyWith({String? avatarUrl}) => Friend(
    id: id,
    username: username,
    displayName: displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    avatarStoragePath: avatarStoragePath,
    cachedAvatarPath:
        avatarStoragePath != null ||
            avatarUrl == null ||
            avatarUrl == this.avatarUrl
        ? cachedAvatarPath
        : null,
    friendsSince: friendsSince,
  );

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    cachedAvatarPath,
    friendsSince,
  ];
}
