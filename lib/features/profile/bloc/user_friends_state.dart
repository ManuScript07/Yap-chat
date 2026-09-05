import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

enum UserFriendsStatus { initial, loading, ready, failure }

enum UserFriendsAction { add, cancel, accept, reject }

class UserFriendsState extends Equatable {
  const UserFriendsState({
    this.status = UserFriendsStatus.initial,
    this.friends = const [],
    this.totalFriendCount = 0,
    this.hasMore = false,
    this.query = '',
    this.isLoadingFirstPage = false,
    this.isLoadingMore = false,
    this.ownFriends = const [],
    this.requests = const [],
    this.hasOwnFriendsSnapshot = false,
    this.hasRequestsSnapshot = false,
    this.pendingFriendIds = const {},
    this.actionErrorId = 0,
  });

  final UserFriendsStatus status;
  final List<ViewedProfileFriend> friends;
  final int totalFriendCount;
  final bool hasMore;
  final String query;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final List<Friend> ownFriends;
  final List<FriendRequest> requests;
  final bool hasOwnFriendsSnapshot;
  final bool hasRequestsSnapshot;
  final Set<String> pendingFriendIds;
  final int actionErrorId;

  List<ViewedProfileFriend> get visibleFriends {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return friends;
    final usernameQuery = normalized.startsWith('@')
        ? normalized.substring(1)
        : normalized;
    return friends
        .where(
          (friend) => normalized.startsWith('@')
              ? friend.username.toLowerCase().contains(usernameQuery)
              : friend.displayName.toLowerCase().contains(normalized) ||
                    friend.username.toLowerCase().contains(usernameQuery),
        )
        .toList(growable: false);
  }

  bool get isSearching => query.trim().isNotEmpty;

  bool get hasRelationshipSnapshot =>
      hasOwnFriendsSnapshot && hasRequestsSnapshot;

  bool isActionPending(String friendId) => pendingFriendIds.contains(friendId);

  ({FriendRelationship relationship, String? requestId}) relationFor(
    String friendId,
  ) {
    if (ownFriends.any((friend) => friend.id == friendId)) {
      return (relationship: FriendRelationship.friend, requestId: null);
    }
    for (final request in requests) {
      if (request.peerId == friendId) {
        return (
          relationship: request.direction == FriendRequestDirection.incoming
              ? FriendRelationship.incoming
              : FriendRelationship.outgoing,
          requestId: request.id,
        );
      }
    }
    return (relationship: FriendRelationship.none, requestId: null);
  }

  UserFriendsState copyWith({
    UserFriendsStatus? status,
    List<ViewedProfileFriend>? friends,
    int? totalFriendCount,
    bool? hasMore,
    String? query,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    List<Friend>? ownFriends,
    List<FriendRequest>? requests,
    bool? hasOwnFriendsSnapshot,
    bool? hasRequestsSnapshot,
    Set<String>? pendingFriendIds,
    int? actionErrorId,
  }) => UserFriendsState(
    status: status ?? this.status,
    friends: friends ?? this.friends,
    totalFriendCount: totalFriendCount ?? this.totalFriendCount,
    hasMore: hasMore ?? this.hasMore,
    query: query ?? this.query,
    isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    ownFriends: ownFriends ?? this.ownFriends,
    requests: requests ?? this.requests,
    hasOwnFriendsSnapshot: hasOwnFriendsSnapshot ?? this.hasOwnFriendsSnapshot,
    hasRequestsSnapshot: hasRequestsSnapshot ?? this.hasRequestsSnapshot,
    pendingFriendIds: pendingFriendIds ?? this.pendingFriendIds,
    actionErrorId: actionErrorId ?? this.actionErrorId,
  );

  @override
  List<Object?> get props => [
    status,
    friends,
    totalFriendCount,
    hasMore,
    query,
    isLoadingFirstPage,
    isLoadingMore,
    ownFriends,
    requests,
    hasOwnFriendsSnapshot,
    hasRequestsSnapshot,
    pendingFriendIds,
    actionErrorId,
  ];
}
