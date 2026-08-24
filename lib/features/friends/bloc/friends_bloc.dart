import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/friends/bloc/friends_event.dart';
import 'package:yap_chat/features/friends/bloc/friends_state.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  FriendsBloc({required IFriendsRepository repository})
    : _repository = repository,
      super(const FriendsState()) {
    on<FriendsLoadStarted>(_onLoadStarted);
    on<FriendsTabChanged>(_onTabChanged);
    on<FriendsSearchChanged>(_onSearchChanged);
    on<FriendRequestCancelled>(_onRequestCancelled);
    on<FriendRequestResponded>(_onRequestResponded);
    on<FriendsActionFailureCleared>(
      (_, emit) => emit(state.copyWith(clearActionError: true)),
    );
    on<FriendsCacheUpdated>(_onFriendsUpdated);
    on<FriendRequestsCacheUpdated>(_onRequestsUpdated);
    on<FriendsWatchFailed>(
      (_, emit) => emit(state.copyWith(status: FriendsStatus.failure)),
    );
  }

  final IFriendsRepository _repository;
  StreamSubscription<List<Friend>>? _friendsSubscription;
  StreamSubscription<List<FriendRequest>>? _requestsSubscription;

  Future<void> _onLoadStarted(
    FriendsLoadStarted event,
    Emitter<FriendsState> emit,
  ) async {
    emit(state.copyWith(status: FriendsStatus.loading, clearActionError: true));
    await _friendsSubscription?.cancel();
    await _requestsSubscription?.cancel();
    _friendsSubscription = _repository.watchFriends().listen(
      (friends) => add(FriendsCacheUpdated(friends)),
      onError: (_, _) => add(const FriendsWatchFailed()),
    );
    _requestsSubscription = _repository.watchRequests().listen(
      (requests) => add(FriendRequestsCacheUpdated(requests)),
      onError: (_, _) => add(const FriendsWatchFailed()),
    );
  }

  void _onTabChanged(FriendsTabChanged event, Emitter<FriendsState> emit) {
    emit(state.copyWith(activeTab: event.tab));
  }

  void _onSearchChanged(
    FriendsSearchChanged event,
    Emitter<FriendsState> emit,
  ) {
    if (state.activeTab == FriendsTab.friends) {
      emit(state.copyWith(friendsQuery: event.query));
    } else {
      emit(state.copyWith(requestsQuery: event.query));
    }
  }

  Future<void> _onRequestCancelled(
    FriendRequestCancelled event,
    Emitter<FriendsState> emit,
  ) async {
    try {
      await _repository.cancelRequest(event.requestId);
    } catch (error) {
      emit(state.copyWith(actionError: error));
    }
  }

  Future<void> _onRequestResponded(
    FriendRequestResponded event,
    Emitter<FriendsState> emit,
  ) async {
    try {
      await _repository.respondToRequest(event.requestId, accept: event.accept);
    } catch (error) {
      emit(state.copyWith(actionError: error));
    }
  }

  void _onFriendsUpdated(
    FriendsCacheUpdated event,
    Emitter<FriendsState> emit,
  ) {
    emit(state.copyWith(status: FriendsStatus.success, friends: event.friends));
  }

  void _onRequestsUpdated(
    FriendRequestsCacheUpdated event,
    Emitter<FriendsState> emit,
  ) {
    emit(
      state.copyWith(status: FriendsStatus.success, requests: event.requests),
    );
  }

  @override
  Future<void> close() async {
    await _friendsSubscription?.cancel();
    await _requestsSubscription?.cancel();
    return super.close();
  }
}
