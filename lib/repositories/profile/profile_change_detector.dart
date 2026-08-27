import 'package:yap_chat/features/profile/data/data.dart';

bool isProfileSaveNoOp({
  required UserProfile currentProfile,
  required String displayName,
  required DateTime birthDate,
  required ProfileGender gender,
  required String username,
  required String bio,
  required List<ProfilePhoto> photos,
}) {
  if (!currentProfile.onboardingCompleted ||
      displayName.trim() != currentProfile.displayName.trim() ||
      birthDate != currentProfile.birthDate ||
      gender != currentProfile.gender ||
      username.trim().toLowerCase() != currentProfile.username.toLowerCase() ||
      bio.trim() != currentProfile.bio.trim()) {
    return false;
  }

  final currentPhotos = currentProfile.effectivePhotos;
  if (photos.length != currentPhotos.length) return false;
  for (var index = 0; index < photos.length; index++) {
    if (photos[index].copyWith(position: index) !=
        currentPhotos[index].copyWith(position: index)) {
      return false;
    }
  }
  return true;
}
