import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/profile/bloc/profile_edit_state.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/profile.dart';

class ProfileEditCubit extends Cubit<ProfileEditState> {
  ProfileEditCubit({
    required IProfileRepository repository,
    required UserProfile initialProfile,
  }) : this._(repository, initialProfile);

  ProfileEditCubit._(this._repository, this._initialProfile)
    : super(const ProfileEditState());

  final IProfileRepository _repository;
  final UserProfile _initialProfile;

  Future<void> submit({
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) async {
    if (state.isSubmitting) return;

    emit(const ProfileEditState(status: ProfileEditStatus.submitting));
    try {
      final profile = await _repository.saveOwnProfile(
        currentProfile: _initialProfile,
        displayName: displayName,
        birthDate: birthDate,
        gender: gender,
        username: username,
        bio: bio,
        photos: List<ProfilePhoto>.unmodifiable(photos),
      );
      if (isClosed) return;
      emit(
        ProfileEditState(
          status: ProfileEditStatus.success,
          savedProfile: profile,
        ),
      );
    } on UsernameAlreadyTakenException {
      if (!isClosed) {
        emit(
          const ProfileEditState(
            status: ProfileEditStatus.failure,
            failure: ProfileEditFailure.usernameTaken,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          const ProfileEditState(
            status: ProfileEditStatus.failure,
            failure: ProfileEditFailure.save,
          ),
        );
      }
    }
  }
}
