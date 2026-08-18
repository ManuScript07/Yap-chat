import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';

class ProfileRepository implements IProfileRepository {
  ProfileRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    final existing = await _client
        .from('profiles')
        .select()
        .eq('id', session.userId)
        .maybeSingle();
    if (existing != null) {
      return _fillMissingYandexData(UserProfile.fromMap(existing), session);
    }

    try {
      final acceptedAt = DateTime.now().toUtc().toIso8601String();
      final created = await _client
          .from('profiles')
          .insert({
            'id': session.userId,
            'display_name': session.displayName ?? '',
            'birth_date': session.birthDate?.toIso8601String().split('T').first,
            'avatar_url': session.avatarUrl,
            'terms_accepted_at': acceptedAt,
            'privacy_accepted_at': acceptedAt,
          })
          .select()
          .single();
      return UserProfile.fromMap(created);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', session.userId)
          .single();
      return _fillMissingYandexData(UserProfile.fromMap(profile), session);
    }
  }

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    String? username,
    String? bio,
  }) async {
    final normalizedUsername = username?.trim().toLowerCase();
    final update = <String, dynamic>{
      'display_name': displayName.trim(),
      'birth_date': birthDate.toIso8601String().split('T').first,
      'gender': gender.databaseValue,
      'bio': bio?.trim() ?? '',
      'onboarding_completed': true,
    };
    if (normalizedUsername != null && normalizedUsername.isNotEmpty) {
      update['username'] = normalizedUsername;
    }

    try {
      final profile = await _client
          .from('profiles')
          .update(update)
          .eq('id', userId)
          .select()
          .single();
      return UserProfile.fromMap(profile);
    } on PostgrestException catch (error) {
      if (error.code == '23505') throw const UsernameAlreadyTakenException();
      rethrow;
    }
  }

  Future<UserProfile> _fillMissingYandexData(
    UserProfile profile,
    AuthSession session,
  ) async {
    final update = <String, dynamic>{};
    if (profile.displayName.isEmpty && session.displayName != null) {
      update['display_name'] = session.displayName;
    }
    if (profile.birthDate == null && session.birthDate != null) {
      update['birth_date'] = session.birthDate!
          .toIso8601String()
          .split('T')
          .first;
    }
    if (profile.avatarUrl == null && session.avatarUrl != null) {
      update['avatar_url'] = session.avatarUrl;
    }
    if (profile.termsAcceptedAt == null || profile.privacyAcceptedAt == null) {
      final acceptedAt = DateTime.now().toUtc().toIso8601String();
      update['terms_accepted_at'] = acceptedAt;
      update['privacy_accepted_at'] = acceptedAt;
    }
    if (update.isEmpty) return profile;

    final updated = await _client
        .from('profiles')
        .update(update)
        .eq('id', session.userId)
        .select()
        .single();
    return UserProfile.fromMap(updated);
  }
}
