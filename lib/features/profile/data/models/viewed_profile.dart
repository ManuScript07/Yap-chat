import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/models/user_profile.dart';

enum ProfileRelationship { none, friend, incoming, outgoing }

class ViewedProfileFriend extends Equatable {
  const ViewedProfileFriend({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
  ];
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
