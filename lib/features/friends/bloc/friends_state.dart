import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/data/data.dart';

enum FriendsStatus { initial, loading, success, failure }

enum FriendsTab { friends, requests }

class FriendsState extends Equatable {
  const FriendsState({
    this.status = FriendsStatus.initial,
    this.activeTab = FriendsTab.friends,
    this.friends = const [],
    this.requests = const [],
    this.friendsQuery = '',
    this.requestsQuery = '',
    this.actionError,
  });

  final FriendsStatus status;
  final FriendsTab activeTab;
  final List<Friend> friends;
  final List<FriendRequest> requests;
  final String friendsQuery;
  final String requestsQuery;
  final Object? actionError;

  String get activeQuery =>
      activeTab == FriendsTab.friends ? friendsQuery : requestsQuery;

  List<Friend> get filteredFriends {
    final query = friendsQuery.trim().toLowerCase();
    if (query.isEmpty) return friends;
    final usernameQuery = query.startsWith('@') ? query.substring(1) : query;
    return friends
        .where(
          (friend) => query.startsWith('@')
              ? friend.username.toLowerCase().contains(usernameQuery)
              : friend.displayName.toLowerCase().contains(query) ||
                    friend.username.toLowerCase().contains(usernameQuery),
        )
        .toList(growable: false);
  }

  List<FriendRequest> get filteredRequests {
    final query = requestsQuery.trim().toLowerCase();
    if (query.isEmpty) return requests;
    final usernameQuery = query.startsWith('@') ? query.substring(1) : query;
    return requests
        .where(
          (request) => query.startsWith('@')
              ? request.peerUsername.toLowerCase().contains(usernameQuery)
              : request.peerDisplayName.toLowerCase().contains(query) ||
                    request.peerUsername.toLowerCase().contains(usernameQuery),
        )
        .toList(growable: false);
  }

  List<FriendRequest> get incomingRequests => filteredRequests
      .where((item) => item.direction == FriendRequestDirection.incoming)
      .toList(growable: false);

  List<FriendRequest> get outgoingRequests => filteredRequests
      .where((item) => item.direction == FriendRequestDirection.outgoing)
      .toList(growable: false);

  int get incomingRequestCount => requests
      .where((item) => item.direction == FriendRequestDirection.incoming)
      .length;

  FriendsState copyWith({
    FriendsStatus? status,
    FriendsTab? activeTab,
    List<Friend>? friends,
    List<FriendRequest>? requests,
    String? friendsQuery,
    String? requestsQuery,
    Object? actionError,
    bool clearActionError = false,
  }) => FriendsState(
    status: status ?? this.status,
    activeTab: activeTab ?? this.activeTab,
    friends: friends ?? this.friends,
    requests: requests ?? this.requests,
    friendsQuery: friendsQuery ?? this.friendsQuery,
    requestsQuery: requestsQuery ?? this.requestsQuery,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    activeTab,
    friends,
    requests,
    friendsQuery,
    requestsQuery,
    actionError,
  ];
}
