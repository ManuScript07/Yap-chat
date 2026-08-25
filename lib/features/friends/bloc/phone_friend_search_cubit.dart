import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

enum PhoneFriendSearchStatus { initial, loading, success, failure }

class PhoneFriendSearchState extends Equatable {
  const PhoneFriendSearchState({
    this.status = PhoneFriendSearchStatus.initial,
    this.phoneNumber = '',
    this.candidate,
    this.isRefreshing = false,
    this.actionError,
  });

  final PhoneFriendSearchStatus status;
  final String phoneNumber;
  final FriendCandidate? candidate;
  final bool isRefreshing;
  final Object? actionError;

  PhoneFriendSearchState copyWith({
    PhoneFriendSearchStatus? status,
    String? phoneNumber,
    FriendCandidate? candidate,
    bool? isRefreshing,
    Object? actionError,
    bool clearCandidate = false,
    bool clearActionError = false,
  }) => PhoneFriendSearchState(
    status: status ?? this.status,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    candidate: clearCandidate ? null : candidate ?? this.candidate,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    phoneNumber,
    candidate,
    isRefreshing,
    actionError,
  ];
}

class PhoneFriendSearchCubit extends Cubit<PhoneFriendSearchState> {
  PhoneFriendSearchCubit({required IFriendsRepository repository})
    : _repository = repository,
      super(const PhoneFriendSearchState());

  final IFriendsRepository _repository;
  int _searchGeneration = 0;

  Future<void> search(String normalizedPhone) async {
    final generation = ++_searchGeneration;
    ContactMatchSnapshot cached = const ContactMatchSnapshot();
    var hasCachedResult = false;
    try {
      cached = await _repository.readCachedContactMatches([normalizedPhone]);
      hasCachedResult = cached.checkedPhoneNumbers.contains(normalizedPhone);
    } catch (_) {
      // Отсутствие локального кэша не должно мешать поиску по сети.
    }
    if (isClosed || generation != _searchGeneration) return;

    if (hasCachedResult) {
      emit(
        PhoneFriendSearchState(
          status: PhoneFriendSearchStatus.success,
          phoneNumber: normalizedPhone,
          candidate: cached.matches[normalizedPhone],
          isRefreshing: true,
        ),
      );
    } else {
      emit(
        PhoneFriendSearchState(
          status: PhoneFriendSearchStatus.loading,
          phoneNumber: normalizedPhone,
        ),
      );
    }

    try {
      final refreshed = await _repository.refreshPhoneMatch(normalizedPhone);
      if (isClosed || generation != _searchGeneration) return;
      final candidate = refreshed.matches[normalizedPhone];
      emit(
        PhoneFriendSearchState(
          status: PhoneFriendSearchStatus.success,
          phoneNumber: normalizedPhone,
          candidate: candidate,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _searchGeneration) return;
      if (!hasCachedResult) {
        emit(
          PhoneFriendSearchState(
            status: PhoneFriendSearchStatus.failure,
            phoneNumber: normalizedPhone,
          ),
        );
      } else {
        emit(state.copyWith(isRefreshing: false));
      }
    }
  }

  Future<void> sendRequest(FriendCandidate candidate) async {
    if (state.candidate?.id != candidate.id ||
        candidate.relationship != FriendRelationship.none) {
      return;
    }
    final previous = state.candidate;
    final optimistic = candidate.copyWith(
      relationship: FriendRelationship.outgoing,
    );
    emit(state.copyWith(candidate: optimistic, clearActionError: true));
    try {
      await _repository.sendRequest(candidate);
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(candidate: previous, actionError: error));
      }
    }
  }

  Future<void> respondToIncoming(
    FriendCandidate candidate, {
    required bool accept,
  }) async {
    final requestId = candidate.requestId;
    if (state.candidate?.id != candidate.id ||
        requestId == null ||
        candidate.relationship != FriendRelationship.incoming) {
      return;
    }
    final previous = state.candidate;
    final optimistic = candidate.copyWith(
      relationship: accept
          ? FriendRelationship.friend
          : FriendRelationship.none,
      clearRequestId: true,
    );
    emit(state.copyWith(candidate: optimistic, clearActionError: true));
    try {
      await _repository.respondToRequest(requestId, accept: accept);
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(candidate: previous, actionError: error));
      }
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));
}
