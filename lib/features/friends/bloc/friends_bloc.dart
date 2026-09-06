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
    on<FriendsLoadMoreRequested>(_onLoadMoreRequested);
    on<FriendsTabChanged>(_onTabChanged);
    on<FriendsSearchChanged>(_onSearchChanged);
    on<FriendRequestCancelled>(_onRequestCancelled);
    on<FriendRequestResponded>(_onRequestResponded);
    on<FriendsActionFailureCleared>(
      (_, emit) => emit(state.copyWith(clearActionError: true)),
    );
    on<FriendsCacheUpdated>(_onFriendsUpdated);
    on<FriendListPaginationUpdated>(_onFriendListPaginationUpdated);
    on<FriendRequestsCacheUpdated>(_onRequestsUpdated);
    on<FriendsWatchFailed>(
      (_, emit) => emit(state.copyWith(status: FriendsStatus.failure)),
    );
  }

  final IFriendsRepository _repository;
  StreamSubscription<List<Friend>>? _friendsSubscription;
  StreamSubscription<FriendListCacheState>? _paginationSubscription;
  StreamSubscription<List<FriendRequest>>? _requestsSubscription;

  Future<void> _onLoadStarted(
    FriendsLoadStarted event,
    Emitter<FriendsState> emit,
  ) async {
    emit(state.copyWith(status: FriendsStatus.loading, clearActionError: true));
    await _friendsSubscription?.cancel();
    await _paginationSubscription?.cancel();
    await _requestsSubscription?.cancel();
    _friendsSubscription = _repository.watchPaginatedFriends().listen(
      (friends) => add(FriendsCacheUpdated(friends)),
      onError: (_, _) => add(const FriendsWatchFailed()),
    );
    _paginationSubscription = _repository.watchFriendListState().listen(
      (pagination) => add(FriendListPaginationUpdated(pagination)),
      onError: (_, _) => add(const FriendsWatchFailed()),
    );
    _requestsSubscription = _repository.watchRequests().listen(
      (requests) => add(FriendRequestsCacheUpdated(requests)),
      onError: (_, _) => add(const FriendsWatchFailed()),
    );
  }

  Future<void> _onLoadMoreRequested(
    FriendsLoadMoreRequested event,
    Emitter<FriendsState> emit,
  ) async {
    if (state.isLoadingMoreFriends || !state.hasMoreFriends) return;
    emit(state.copyWith(isLoadingMoreFriends: true));
    try {
      await _repository.loadMoreFriends();
    } catch (error) {
      emit(state.copyWith(actionError: error));
    } finally {
      emit(state.copyWith(isLoadingMoreFriends: false));
    }
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

  void _onFriendListPaginationUpdated(
    FriendListPaginationUpdated event,
    Emitter<FriendsState> emit,
  ) {
    emit(
      state.copyWith(
        totalFriendCount: event.state.totalCount,
        hasMoreFriends: event.state.hasMore,
      ),
    );
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
    await _paginationSubscription?.cancel();
    await _requestsSubscription?.cancel();
    return super.close();
  }
}
