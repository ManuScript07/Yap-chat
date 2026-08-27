import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/bloc/profile_draft.dart';
import 'package:yap_chat/features/profile/data/data.dart';

enum ProfileMutationStatus { idle, submitting, success, failure }

enum ProfileMutationFailure { usernameTaken, save }

class ProfileMutationState extends Equatable {
  const ProfileMutationState({
    this.status = ProfileMutationStatus.idle,
    this.operationId,
    this.draft,
    this.savedProfile,
    this.failure,
  });

  final ProfileMutationStatus status;
  final String? operationId;
  final ProfileDraft? draft;
  final UserProfile? savedProfile;
  final ProfileMutationFailure? failure;

  bool get isSubmitting => status == ProfileMutationStatus.submitting;

  @override
  List<Object?> get props => [
    status,
    operationId,
    draft,
    savedProfile,
    failure,
  ];
}
