import 'package:equatable/equatable.dart';

enum FriendRequestDirection { incoming, outgoing }

class FriendRequest extends Equatable {
  const FriendRequest({
    required this.id,
    required this.peerId,
    required this.peerUsername,
    required this.peerDisplayName,
    required this.direction,
    required this.requestedAt,
    this.peerAvatarUrl,
    this.peerAvatarStoragePath,
    this.peerFriendCount,
  });

  final String id;
  final String peerId;
  final String peerUsername;
  final String peerDisplayName;
  final String? peerAvatarUrl;
  final String? peerAvatarStoragePath;
  final int? peerFriendCount;
  final FriendRequestDirection direction;
  final DateTime requestedAt;

  FriendRequest copyWith({String? peerAvatarUrl}) => FriendRequest(
    id: id,
    peerId: peerId,
    peerUsername: peerUsername,
    peerDisplayName: peerDisplayName,
    peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
    peerAvatarStoragePath: peerAvatarStoragePath,
    peerFriendCount: peerFriendCount,
    direction: direction,
    requestedAt: requestedAt,
  );

  @override
  List<Object?> get props => [
    id,
    peerId,
    peerUsername,
    peerDisplayName,
    peerAvatarUrl,
    peerAvatarStoragePath,
    peerFriendCount,
    direction,
    requestedAt,
  ];
}
