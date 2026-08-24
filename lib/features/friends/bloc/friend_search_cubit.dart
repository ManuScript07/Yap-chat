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
  bool _searchInProgress = false;
  ({String query, int generation})? _pendingSearch;

  void queryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    if (!_isGlobalQuery(query)) {
      _pendingSearch = null;
      emit(FriendSearchState(status: FriendSearchStatus.initial, query: value));
      return;
    }
    emit(
      state.copyWith(
        status: FriendSearchStatus.loading,
        query: value,
        clearActionError: true,
      ),
    );
    _debounce = Timer(
      const Duration(milliseconds: 375),
      () => _scheduleSearch(query, generation),
    );
  }

  bool _isGlobalQuery(String query) {
    if (query.startsWith('@')) return query.substring(1).length >= 3;
    return query.length >= 3;
  }

  void _scheduleSearch(String query, int generation) {
    if (_searchInProgress) {
      _pendingSearch = (query: query, generation: generation);
      return;
    }
    unawaited(_runSearch(query, generation));
  }

  Future<void> _runSearch(String query, int generation) async {
    _searchInProgress = true;
    try {
      final results = await _repository.searchUsers(query);
      if (!isClosed && generation == _searchGeneration) {
        emit(
          state.copyWith(status: FriendSearchStatus.success, results: results),
        );
      }
    } catch (_) {
      if (!isClosed && generation == _searchGeneration) {
        emit(state.copyWith(status: FriendSearchStatus.failure));
      }
    } finally {
      _searchInProgress = false;
      final pending = _pendingSearch;
      _pendingSearch = null;
      if (!isClosed &&
          pending != null &&
          pending.generation == _searchGeneration) {
        await _runSearch(pending.query, pending.generation);
      }
    }
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

  Future<void> respondToIncoming(
    FriendCandidate candidate, {
    required bool accept,
  }) async {
    final requestId = candidate.requestId;
    final index = state.results.indexWhere((item) => item.id == candidate.id);
    if (requestId == null ||
        index < 0 ||
        candidate.relationship != FriendRelationship.incoming) {
      return;
    }
    final previous = state.results;
    final optimistic = [...previous];
    if (accept) {
      optimistic.removeAt(index);
    } else {
      optimistic[index] = candidate.copyWith(
        relationship: FriendRelationship.none,
        clearRequestId: true,
      );
    }
    emit(state.copyWith(results: optimistic, clearActionError: true));
    try {
      await _repository.respondToRequest(requestId, accept: accept);
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
