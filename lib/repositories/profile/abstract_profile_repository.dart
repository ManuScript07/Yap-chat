import 'dart:typed_data';

import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

abstract interface class IProfileRepository {
  Future<UserProfile?> getCachedProfile(String userId);

  Future<UserProfile> getOrCreateProfile(AuthSession session);

  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    String? username,
    String? bio,
    Uint8List? avatarBytes,
    bool removeAvatar = false,
  });
}

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}
