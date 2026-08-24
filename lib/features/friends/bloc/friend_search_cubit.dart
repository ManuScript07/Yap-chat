import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

enum FriendSearchStatus { initial, loading, success, failure }

class FriendSearchState extends Equatable {
  const FriendSearchState({
    this.status = FriendSearchStatus.initial,
    this.query = '',
    this.results = const [],
    this.actionError,
  });

  final FriendSearchStatus status;
  final String query;
  final List<FriendCandidate> results;
  final Object? actionError;

  FriendSearchState copyWith({
    FriendSearchStatus? status,
    String? query,
    List<FriendCandidate>? results,
    Object? actionError,
    bool clearActionError = false,
  }) => FriendSearchState(
    status: status ?? this.status,
    query: query ?? this.query,
    results: results ?? this.results,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [status, query, results, actionError];
}

class FriendSearchCubit extends Cubit<FriendSearchState> {
  FriendSearchCubit({required IFriendsRepository repository})
    : _repository = repository,
      super(const FriendSearchState());

  final IFriendsRepository _repository;
  Timer? _debounce;
  int _searchGeneration = 0;

  void queryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    if (query.isEmpty) {
      emit(
        const FriendSearchState(status: FriendSearchStatus.initial, query: ''),
      );
      return;
    }
    emit(
      state.copyWith(
        status: FriendSearchStatus.loading,
        query: value,
        clearActionError: true,
      ),
    );
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _repository.searchUsers(query);
        if (!isClosed && generation == _searchGeneration) {
          emit(
            state.copyWith(
              status: FriendSearchStatus.success,
              results: results,
            ),
          );
        }
      } catch (error) {
        if (!isClosed && generation == _searchGeneration) {
          emit(state.copyWith(status: FriendSearchStatus.failure));
        }
      }
    });
  }

  Future<void> sendRequest(FriendCandidate candidate) async {
    final index = state.results.indexWhere((item) => item.id == candidate.id);
    if (index < 0 || candidate.relationship != FriendRelationship.none) return;
    final previous = state.results;
    final optimistic = [...previous];
    optimistic[index] = candidate.copyWith(
      relationship: FriendRelationship.outgoing,
    );
    emit(state.copyWith(results: optimistic, clearActionError: true));
    try {
      await _repository.sendRequest(candidate);
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(results: previous, actionError: error));
      }
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
