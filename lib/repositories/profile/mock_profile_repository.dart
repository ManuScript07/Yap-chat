import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  Future<UserProfile?> getCachedProfile(String userId) async {
    final saved = _preferences.getString(_storageKey);
    if (saved == null) return null;

    final profile = _profileFromJson(saved);
    return profile.id == userId ? profile : null;
  }

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final saved = _preferences.getString(_storageKey);
    if (saved != null) {
      final profile = _profileFromJson(saved);
      return _acceptMissingDocuments(profile);
    }

    final acceptedAt = DateTime.now().toUtc();
    final profile = UserProfile(
      id: session.userId,
      username: _generateUsername(),
      displayName: session.displayName ?? '',
      birthDate: session.birthDate,
      avatarUrl: session.avatarUrl,
      onboardingCompleted: false,
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
      createdAt: acceptedAt,
    );
    await _save(profile);
    return profile;
  }

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    String? username,
    String? bio,
    Uint8List? avatarBytes,
    List<ProfilePhoto>? photos,
    bool removeAvatar = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final current = await getOrCreateProfile(AuthSession(userId: userId));
    final effectivePhotos =
        photos ??
        (avatarBytes != null
            ? [ProfilePhoto(position: 0, bytes: avatarBytes)]
            : removeAvatar
            ? const <ProfilePhoto>[]
            : current.effectivePhotos);
    final normalizedPhotos = [
      for (var index = 0; index < effectivePhotos.length; index++)
        effectivePhotos[index].copyWith(position: index),
    ];
    final primary = normalizedPhotos.firstOrNull;
    final profile = current.copyWith(
      displayName: displayName.trim(),
      birthDate: birthDate,
      username: username?.trim().isNotEmpty == true
          ? username!.trim().toLowerCase()
          : current.username,
      gender: gender,
      bio: bio?.trim() ?? '',
      onboardingCompleted: true,
      photos: normalizedPhotos,
      avatarUrl: primary?.avatarUrl,
      avatarStoragePath: primary?.storagePath,
      avatarBytes: primary?.bytes,
      avatarUpdatedAt: primary?.updatedAt,
      clearAvatarUrl: primary?.avatarUrl == null,
      clearAvatarStoragePath: primary?.storagePath == null,
      clearAvatarBytes: primary?.bytes == null,
      clearAvatarUpdatedAt: primary?.updatedAt == null,
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

  Future<UserProfile> _acceptMissingDocuments(UserProfile profile) async {
    if (profile.termsAcceptedAt != null && profile.privacyAcceptedAt != null) {
      return profile;
    }

    final acceptedAt = DateTime.now().toUtc();
    final updated = UserProfile(
      id: profile.id,
      username: profile.username,
      displayName: profile.displayName,
      birthDate: profile.birthDate,
      avatarUrl: profile.avatarUrl,
      avatarStoragePath: profile.avatarStoragePath,
      avatarBytes: profile.avatarBytes,
      avatarUpdatedAt: profile.avatarUpdatedAt,
      photos: profile.photos,
      gender: profile.gender,
      bio: profile.bio,
      onboardingCompleted: profile.onboardingCompleted,
      termsAcceptedAt: profile.termsAcceptedAt ?? acceptedAt,
      privacyAcceptedAt: profile.privacyAcceptedAt ?? acceptedAt,
      createdAt: profile.createdAt ?? acceptedAt,
    );
    await _save(updated);
    return updated;
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
        'avatar_storage_path': profile.avatarStoragePath,
        'avatar_bytes': profile.avatarBytes == null
            ? null
            : base64Encode(profile.avatarBytes!),
        'avatar_updated_at': profile.avatarUpdatedAt?.toIso8601String(),
        'gender': profile.gender.databaseValue,
        'bio': profile.bio,
        'onboarding_completed': profile.onboardingCompleted,
        'terms_accepted_at': profile.termsAcceptedAt?.toIso8601String(),
        'privacy_accepted_at': profile.privacyAcceptedAt?.toIso8601String(),
        'created_at': profile.createdAt?.toIso8601String(),
        'photos': profile.photos
            .map(
              (photo) => {
                'position': photo.position,
                'avatar_url': photo.avatarUrl,
                'storage_path': photo.storagePath,
                'bytes': photo.bytes == null
                    ? null
                    : base64Encode(photo.bytes!),
                'updated_at': photo.updatedAt?.toIso8601String(),
              },
            )
            .toList(growable: false),
      }),
    );
  }

  UserProfile _profileFromJson(String value) {
    final map = Map<String, dynamic>.from(jsonDecode(value) as Map);
    final encodedAvatar = map.remove('avatar_bytes') as String?;
    final photoMaps = (map.remove('photos') as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final parsed = UserProfile.fromMap(map).copyWith(
      avatarBytes: encodedAvatar == null ? null : base64Decode(encodedAvatar),
      photos: photoMaps
          .map(
            (photo) => ProfilePhoto(
              position: photo['position'] as int,
              avatarUrl: photo['avatar_url'] as String?,
              storagePath: photo['storage_path'] as String?,
              bytes: photo['bytes'] == null
                  ? null
                  : base64Decode(photo['bytes'] as String),
              updatedAt: DateTime.tryParse(
                photo['updated_at'] as String? ?? '',
              ),
            ),
          )
          .toList(growable: false),
    );
    if (parsed.photos.isNotEmpty ||
        (parsed.avatarUrl == null && parsed.avatarBytes == null)) {
      return parsed;
    }
    return parsed.copyWith(
      photos: [
        ProfilePhoto(
          position: 0,
          avatarUrl: parsed.avatarUrl,
          storagePath: parsed.avatarStoragePath,
          bytes: parsed.avatarBytes,
          updatedAt: parsed.avatarUpdatedAt,
        ),
      ],
    );
  }
}
