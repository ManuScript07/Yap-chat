import 'package:equatable/equatable.dart';

enum FriendRelationship { none, friend, incoming, outgoing }

class FriendCandidate extends Equatable {
  const FriendCandidate({
    required this.id,
    required this.username,
    required this.displayName,
    required this.relationship,
    this.requestId,
    this.avatarUrl,
    this.avatarStoragePath,
    this.friendCount,
  });

  final String id;
  final String? requestId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final int? friendCount;
  final FriendRelationship relationship;

  FriendCandidate copyWith({
    FriendRelationship? relationship,
    String? avatarUrl,
    String? requestId,
    bool clearRequestId = false,
  }) => FriendCandidate(
    id: id,
    requestId: clearRequestId ? null : requestId ?? this.requestId,
    username: username,
    displayName: displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    avatarStoragePath: avatarStoragePath,
    friendCount: friendCount,
    relationship: relationship ?? this.relationship,
  );

  @override
  List<Object?> get props => [
    id,
    requestId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    friendCount,
    relationship,
  ];
}
