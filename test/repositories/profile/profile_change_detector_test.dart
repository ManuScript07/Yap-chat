import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/repositories/profile/profile.dart';

void main() {
  test('recognizes a normalized unchanged completed profile', () {
    final profile = _profile(onboardingCompleted: true);

    final isNoOp = isProfileSaveNoOp(
      currentProfile: profile,
      displayName: '  User  ',
      birthDate: profile.birthDate!,
      gender: profile.gender,
      username: '  USER_NAME  ',
      bio: '  Bio  ',
      photos: profile.effectivePhotos,
    );

    expect(isNoOp, isTrue);
  });

  test('never skips the save that completes onboarding', () {
    final profile = _profile(onboardingCompleted: false);

    final isNoOp = isProfileSaveNoOp(
      currentProfile: profile,
      displayName: profile.displayName,
      birthDate: profile.birthDate!,
      gender: profile.gender,
      username: profile.username,
      bio: profile.bio,
      photos: profile.effectivePhotos,
    );

    expect(isNoOp, isFalse);
  });
}

UserProfile _profile({required bool onboardingCompleted}) {
  final acceptedAt = DateTime.utc(2026);
  return UserProfile(
    id: 'user',
    username: 'user_name',
    displayName: 'User',
    birthDate: DateTime(2000),
    gender: ProfileGender.unspecified,
    bio: 'Bio',
    onboardingCompleted: onboardingCompleted,
    termsAcceptedAt: acceptedAt,
    privacyAcceptedAt: acceptedAt,
    photos: const [ProfilePhoto(position: 0, storagePath: 'user/avatar.jpg')],
  );
}
