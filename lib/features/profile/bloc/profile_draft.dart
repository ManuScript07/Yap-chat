import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/data.dart';

class ProfileDraft extends Equatable {
  const ProfileDraft({
    required this.userId,
    required this.displayName,
    required this.birthDate,
    required this.gender,
    required this.username,
    required this.bio,
    required this.photos,
  });

  factory ProfileDraft.fromProfile(UserProfile profile) {
    return ProfileDraft(
      userId: profile.id,
      displayName: profile.displayName,
      birthDate: profile.birthDate!,
      gender: profile.gender,
      username: profile.username,
      bio: profile.bio,
      photos: profile.effectivePhotos,
    ).normalized();
  }

  final String userId;
  final String displayName;
  final DateTime birthDate;
  final ProfileGender gender;
  final String username;
  final String bio;
  final List<ProfilePhoto> photos;

  ProfileDraft normalized() {
    return ProfileDraft(
      userId: userId,
      displayName: displayName.trim(),
      birthDate: birthDate,
      gender: gender,
      username: username.trim().toLowerCase(),
      bio: bio.trim(),
      photos: List<ProfilePhoto>.unmodifiable([
        for (var index = 0; index < photos.length; index++)
          photos[index].copyWith(position: index),
      ]),
    );
  }

  bool hasSameContent(UserProfile profile) =>
      normalized() == ProfileDraft.fromProfile(profile);

  @override
  List<Object?> get props => [
    userId,
    displayName,
    birthDate,
    gender,
    username,
    bio,
    photos,
  ];
}
