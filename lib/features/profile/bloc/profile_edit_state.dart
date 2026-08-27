import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/data.dart';

enum ProfileEditStatus { initial, submitting, success, failure }

enum ProfileEditFailure { usernameTaken, save }

class ProfileEditState extends Equatable {
  const ProfileEditState({
    this.status = ProfileEditStatus.initial,
    this.failure,
    this.savedProfile,
  });

  final ProfileEditStatus status;
  final ProfileEditFailure? failure;
  final UserProfile? savedProfile;

  bool get isSubmitting => status == ProfileEditStatus.submitting;

  @override
  List<Object?> get props => [status, failure, savedProfile];
}
