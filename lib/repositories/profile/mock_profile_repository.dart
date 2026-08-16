import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';

class MockProfileRepository implements IProfileRepository {
  MockProfileRepository({required SharedPreferences preferences})
    : _preferences = preferences;

  static const _storageKey = 'mock_user_profile';
  static const _usernameCharacters = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final SharedPreferences _preferences;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final saved = _preferences.getString(_storageKey);
    if (saved != null) {
      return UserProfile.fromMap(
        Map<String, dynamic>.from(jsonDecode(saved) as Map),
      );
    }

    final profile = UserProfile(
      id: session.userId,
      username: _generateUsername(),
      displayName: session.displayName ?? '',
      birthDate: session.birthDate,
      avatarUrl: session.avatarUrl,
      onboardingCompleted: false,
    );
    await _save(profile);
    return profile;
  }

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required bool acceptedTerms,
    String? username,
    String? avatarUrl,
  }) async {
    if (!acceptedTerms) {
      throw StateError('Terms and privacy policy must be accepted.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 450));
    final now = DateTime.now().toUtc();
    final current = await getOrCreateProfile(AuthSession(userId: userId));
    final profile = current.copyWith(
      displayName: displayName.trim(),
      birthDate: birthDate,
      username: username?.trim().isNotEmpty == true
          ? username!.trim().toLowerCase()
          : current.username,
      avatarUrl: avatarUrl,
      onboardingCompleted: true,
      termsAcceptedAt: now,
      privacyAcceptedAt: now,
    );
    await _save(profile);
    return profile;
  }

  String _generateUsername() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => _usernameCharacters[random.nextInt(_usernameCharacters.length)],
    ).join();
  }

  Future<void> _save(UserProfile profile) {
    return _preferences.setString(
      _storageKey,
      jsonEncode({
        'id': profile.id,
        'username': profile.username,
        'display_name': profile.displayName,
        'birth_date': profile.birthDate?.toIso8601String(),
        'avatar_url': profile.avatarUrl,
        'onboarding_completed': profile.onboardingCompleted,
        'terms_accepted_at': profile.termsAcceptedAt?.toIso8601String(),
        'privacy_accepted_at': profile.privacyAcceptedAt?.toIso8601String(),
      }),
    );
  }
}
