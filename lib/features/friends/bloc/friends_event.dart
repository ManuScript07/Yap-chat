import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/bloc/friends_state.dart';
import 'package:yap_chat/features/friends/data/data.dart';

sealed class FriendsEvent extends Equatable {
  const FriendsEvent();

  @override
  List<Object?> get props => [];
}

final class FriendsLoadStarted extends FriendsEvent {
  const FriendsLoadStarted();
}

final class FriendsTabChanged extends FriendsEvent {
  const FriendsTabChanged(this.tab);

  final FriendsTab tab;

  @override
  List<Object?> get props => [tab];
}

final class FriendsSearchChanged extends FriendsEvent {
  const FriendsSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

final class FriendRequestCancelled extends FriendsEvent {
  const FriendRequestCancelled(this.requestId);

  final String requestId;

  @override
  List<Object?> get props => [requestId];
}

final class FriendRequestResponded extends FriendsEvent {
  const FriendRequestResponded(this.requestId, {required this.accept});

  final String requestId;
  final bool accept;

  @override
  List<Object?> get props => [requestId, accept];
}

final class FriendsActionFailureCleared extends FriendsEvent {
  const FriendsActionFailureCleared();
}

final class FriendsCacheUpdated extends FriendsEvent {
  const FriendsCacheUpdated(this.friends);

  final List<Friend> friends;

  @override
  List<Object?> get props => [friends];
}

final class FriendRequestsCacheUpdated extends FriendsEvent {
  const FriendRequestsCacheUpdated(this.requests);

  final List<FriendRequest> requests;

  @override
  List<Object?> get props => [requests];
}

final class FriendsWatchFailed extends FriendsEvent {
  const FriendsWatchFailed();
}
