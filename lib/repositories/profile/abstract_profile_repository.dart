import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

abstract interface class IProfileRepository {
  Future<UserProfile> getOrCreateProfile(AuthSession session);

  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required bool acceptedTerms,
    String? username,
    String? avatarUrl,
  });
}

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}
