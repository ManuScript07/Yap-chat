import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/bloc/user_friends_state.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

class UserFriendsCubit extends Cubit<UserFriendsState> {
  UserFriendsCubit({
    required this.userId,
    required this.profileRepository,
    required this.friendsRepository,
  }) : super(const UserFriendsState()) {
    _friendsSubscription = friendsRepository.watchCachedFriends().listen(
      (friends) => _emitIfOpen(
        state.copyWith(ownFriends: friends, hasOwnFriendsSnapshot: true),
      ),
    );
    _requestsSubscription = friendsRepository.watchCachedRequests().listen(
      (requests) => _emitIfOpen(
        state.copyWith(requests: requests, hasRequestsSnapshot: true),
      ),
    );
  }

  static const cacheTtl = Duration(minutes: 10);
  static const _maximumRequestsPerMinute = 8;

  final String userId;
  final IProfileRepository profileRepository;
  final IFriendsRepository friendsRepository;
  final List<DateTime> _requestStarts = [];
  late final StreamSubscription<List<Friend>> _friendsSubscription;
  late final StreamSubscription<List<FriendRequest>> _requestsSubscription;
  Future<void>? _initialization;

  Future<void> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final future = _initialize();
    _initialization = future;
    return future;
  }

  Future<void> _initialize() async {
    final cachedProfileFuture = profileRepository.getCachedViewedProfile(
      userId,
    );
    ViewedProfileFriendsSnapshot? snapshot;
    try {
      snapshot = await profileRepository.getCachedViewedProfileFriendsSnapshot(
        userId,
      );
    } catch (_) {
      // A damaged friend-list cache must not prevent the remote first page.
    }

    ViewedProfile? cachedProfile;
    try {
      cachedProfile = await cachedProfileFuture;
    } catch (_) {
      // The total can safely fall back to the locally loaded page.
    }
    if (isClosed) return;

    final total = cachedProfile?.friendCount ?? snapshot?.friends.length ?? 0;
    if (snapshot != null) {
      emit(
        state.copyWith(
          status: UserFriendsStatus.ready,
          friends: snapshot.friends,
          hasMore: snapshot.hasMore,
          totalFriendCount: total,
        ),
      );
      if (DateTime.now().toUtc().difference(snapshot.cachedAt) < cacheTtl) {
        return;
      }
    } else {
      emit(state.copyWith(status: UserFriendsStatus.loading));
    }
    await _loadFirstPage();
  }

  void searchChanged(String query) {
    if (query == state.query) return;
    _emitIfOpen(state.copyWith(query: query));
  }

  bool _consumeRequestBudget() {
    final now = DateTime.now();
    _requestStarts.removeWhere(
      (startedAt) => now.difference(startedAt) >= const Duration(minutes: 1),
    );
    if (_requestStarts.length >= _maximumRequestsPerMinute) return false;
    _requestStarts.add(now);
    return true;
  }

  Future<void> _loadFirstPage() async {
    if (state.isLoadingFirstPage ||
        state.isLoadingMore ||
        !_consumeRequestBudget()) {
      return;
    }
    _emitIfOpen(
      state.copyWith(
        isLoadingFirstPage: true,
        status: state.friends.isEmpty
            ? UserFriendsStatus.loading
            : UserFriendsStatus.ready,
      ),
    );
    try {
      final page = await profileRepository.refreshViewedProfileFriends(userId);
      _emitIfOpen(
        state.copyWith(
          status: UserFriendsStatus.ready,
          friends: page.friends,
          hasMore: page.hasMore,
          totalFriendCount: state.totalFriendCount == 0
              ? page.friends.length
              : state.totalFriendCount,
          isLoadingFirstPage: false,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      _emitIfOpen(
        state.copyWith(
          status: state.friends.isEmpty
              ? UserFriendsStatus.failure
              : UserFriendsStatus.ready,
          isLoadingFirstPage: false,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.status != UserFriendsStatus.ready ||
        state.isSearching ||
        state.isLoadingFirstPage ||
        state.isLoadingMore ||
        !state.hasMore ||
        !_consumeRequestBudget()) {
      return;
    }
    _emitIfOpen(state.copyWith(isLoadingMore: true));
    try {
      final snapshot = await profileRepository.loadMoreViewedProfileFriends(
        userId,
      );
      if (snapshot != null) {
        _emitIfOpen(
          state.copyWith(
            friends: snapshot.friends,
            hasMore: snapshot.hasMore,
            isLoadingMore: false,
          ),
        );
      } else {
        _emitIfOpen(state.copyWith(isLoadingMore: false));
      }
    } catch (_) {
      _emitIfOpen(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> performAction(
    ViewedProfileFriend friend,
    UserFriendsAction action,
  ) async {
    if (state.isActionPending(friend.id)) return;
    final relation = state.relationFor(friend.id);
    if (action != UserFriendsAction.add && relation.requestId == null) return;
    _emitIfOpen(
      state.copyWith(pendingFriendIds: {...state.pendingFriendIds, friend.id}),
    );
    try {
      switch (action) {
        case UserFriendsAction.add:
          await friendsRepository.sendRequest(
            FriendCandidate(
              id: friend.id,
              username: friend.username,
              displayName: friend.displayName,
              avatarUrl: friend.avatarUrl,
              avatarStoragePath: friend.avatarStoragePath,
              relationship: FriendRelationship.none,
            ),
          );
        case UserFriendsAction.cancel:
          await friendsRepository.cancelRequest(relation.requestId!);
        case UserFriendsAction.accept:
          await friendsRepository.respondToRequest(
            relation.requestId!,
            accept: true,
          );
        case UserFriendsAction.reject:
          await friendsRepository.respondToRequest(
            relation.requestId!,
            accept: false,
          );
      }
    } catch (_) {
      _emitIfOpen(state.copyWith(actionErrorId: state.actionErrorId + 1));
    } finally {
      if (!isClosed) {
        final pending = {...state.pendingFriendIds}..remove(friend.id);
        emit(state.copyWith(pendingFriendIds: pending));
      }
    }
  }

  void _emitIfOpen(UserFriendsState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    await _friendsSubscription.cancel();
    await _requestsSubscription.cancel();
    return super.close();
  }
}
