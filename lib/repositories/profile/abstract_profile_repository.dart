import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

abstract interface class IProfileRepository {
  Future<UserProfile?> getCachedProfile(String userId);

  Future<UserProfile> getOrCreateProfile(AuthSession session);

  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  });
}

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}
