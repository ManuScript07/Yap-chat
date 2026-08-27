import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/features/profile/bloc/profile_draft.dart';
import 'package:yap_chat/features/profile/bloc/profile_mutation_state.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/profile.dart';

class ProfileMutationCubit extends Cubit<ProfileMutationState> {
  ProfileMutationCubit({
    required IProfileRepository repository,
    Uuid uuid = const Uuid(),
  }) : this._(repository, uuid);

  ProfileMutationCubit._(this._repository, this._uuid)
    : super(const ProfileMutationState());

  final IProfileRepository _repository;
  final Uuid _uuid;
  String? _authenticatedUserId;

  void setAuthenticatedUser(String? userId) {
    if (_authenticatedUserId == userId) return;
    _authenticatedUserId = userId;
    emit(const ProfileMutationState());
  }

  String? submit({
    required UserProfile currentProfile,
    required ProfileDraft draft,
  }) {
    if (state.isSubmitting) return state.operationId;

    final normalizedDraft = draft.normalized();
    if (normalizedDraft.userId != currentProfile.id ||
        (_authenticatedUserId != null &&
            _authenticatedUserId != normalizedDraft.userId)) {
      return null;
    }
    if (normalizedDraft.hasSameContent(currentProfile)) return null;

    _authenticatedUserId ??= normalizedDraft.userId;
    final operationId = _uuid.v4();
    emit(
      ProfileMutationState(
        status: ProfileMutationStatus.submitting,
        operationId: operationId,
        draft: normalizedDraft,
      ),
    );
    unawaited(
      _performSave(
        operationId: operationId,
        currentProfile: currentProfile,
        draft: normalizedDraft,
      ),
    );
    return operationId;
  }

  Future<void> _performSave({
    required String operationId,
    required UserProfile currentProfile,
    required ProfileDraft draft,
  }) async {
    try {
      final profile = await _repository.saveOwnProfile(
        currentProfile: currentProfile,
        displayName: draft.displayName,
        birthDate: draft.birthDate,
        gender: draft.gender,
        username: draft.username,
        bio: draft.bio,
        photos: draft.photos,
      );
      if (isClosed || state.operationId != operationId) return;
      emit(
        ProfileMutationState(
          status: ProfileMutationStatus.success,
          operationId: operationId,
          draft: draft,
          savedProfile: profile,
        ),
      );
    } on UsernameAlreadyTakenException {
      if (!isClosed && state.operationId == operationId) {
        emit(
          ProfileMutationState(
            status: ProfileMutationStatus.failure,
            operationId: operationId,
            draft: draft,
            failure: ProfileMutationFailure.usernameTaken,
          ),
        );
      }
    } catch (_) {
      if (!isClosed && state.operationId == operationId) {
        emit(
          ProfileMutationState(
            status: ProfileMutationStatus.failure,
            operationId: operationId,
            draft: draft,
            failure: ProfileMutationFailure.save,
          ),
        );
      }
    }
  }
}
