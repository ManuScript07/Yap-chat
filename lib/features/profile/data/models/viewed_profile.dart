import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/models/user_profile.dart';

enum ProfileRelationship { none, friend, incoming, outgoing, blocked }

class ViewedProfileFriend extends Equatable {
  const ViewedProfileFriend({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarStoragePath,
    this.mutualFriendCount = 0,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final int mutualFriendCount;

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    mutualFriendCount,
  ];
}

/// One cursor page of another user's visible friends.  The server calculates
/// [ViewedProfileFriend.mutualFriendCount] for this bounded page in the same
/// RPC, so rendering a list never becomes an N+1 request pattern.
class ViewedProfileFriendsPage extends Equatable {
  const ViewedProfileFriendsPage({
    required this.friends,
    required this.hasMore,
  });

  final List<ViewedProfileFriend> friends;
  final bool hasMore;

  @override
  List<Object?> get props => [friends, hasMore];
}

/// A local cache snapshot.  Its timestamp belongs to the assembled list,
/// rather than each row, because a refresh replaces the first page atomically.
class ViewedProfileFriendsSnapshot extends Equatable {
  const ViewedProfileFriendsSnapshot({
    required this.friends,
    required this.hasMore,
    required this.cachedAt,
  });

  final List<ViewedProfileFriend> friends;
  final bool hasMore;
  final DateTime cachedAt;

  @override
  List<Object?> get props => [friends, hasMore, cachedAt];
}

class ViewedProfile extends Equatable {
  const ViewedProfile({
    required this.profile,
    required this.relationship,
    required this.friendCount,
    required this.friendsPreview,
    required this.viewCount,
    required this.showsLastSeen,
    this.requestId,
    this.lastSeenAt,
  });

  final UserProfile profile;
  final ProfileRelationship relationship;
  final String? requestId;
  final int friendCount;
  final List<ViewedProfileFriend> friendsPreview;
  final int viewCount;
  final DateTime? lastSeenAt;
  final bool showsLastSeen;

  bool get isFriend => relationship == ProfileRelationship.friend;
  bool get isBlocked => relationship == ProfileRelationship.blocked;

  ViewedProfile copyWith({
    ProfileRelationship? relationship,
    String? requestId,
    bool clearRequestId = false,
    int? friendCount,
    List<ViewedProfileFriend>? friendsPreview,
    int? viewCount,
    DateTime? lastSeenAt,
    bool? showsLastSeen,
    bool clearLastSeenAt = false,
  }) => ViewedProfile(
    profile: profile,
    relationship: relationship ?? this.relationship,
    requestId: clearRequestId ? null : requestId ?? this.requestId,
    friendCount: friendCount ?? this.friendCount,
    friendsPreview: friendsPreview ?? this.friendsPreview,
    viewCount: viewCount ?? this.viewCount,
    lastSeenAt: clearLastSeenAt ? null : lastSeenAt ?? this.lastSeenAt,
    showsLastSeen: showsLastSeen ?? this.showsLastSeen,
  );

  @override
  List<Object?> get props => [
    profile,
    relationship,
    requestId,
    friendCount,
    friendsPreview,
    viewCount,
    lastSeenAt,
    showsLastSeen,
  ];
}
