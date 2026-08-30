import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';
import 'package:yap_chat/repositories/profile/profile_change_detector.dart';

class MockProfileRepository
    implements IProfileRepository, IViewedProfileRepository {
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
    final normalized = _profileToJson(profile);
    if (normalized != saved) {
      await _preferences.setString(_storageKey, normalized);
    }
    return profile.id == userId ? profile : null;
  }

  @override
  Future<ViewedProfile?> getCachedViewedProfile(String userId) async => null;

  @override
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) async {
    final now = DateTime.now();
    return ViewedProfile(
      profile: UserProfile(
        id: userId,
        username: userId.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_'),
        displayName: 'Пользователь',
        bio: 'Профиль пользователя Yap',
        onboardingCompleted: true,
        createdAt: now.subtract(const Duration(days: 42)),
      ),
      relationship: ProfileRelationship.none,
      friendCount: 0,
      friendsPreview: const [],
      viewCount: 1,
      showsLastSeen: true,
      lastSeenAt: now.subtract(const Duration(minutes: 12)),
    );
  }

  @override
  Future<List<ViewedProfileFriend>> getCachedViewedProfileFriends(
    String userId,
  ) async => const [];

  @override
  Future<List<ViewedProfileFriend>> getViewedProfileFriends(
    String userId,
  ) async => const [];

  @override
  Future<String?> resolveViewedProfileFriendAvatar(
    ViewedProfileFriend friend,
  ) async => friend.avatarUrl;

  @override
  Future<int?> getCachedProfileViewCount(String userId) async => 0;

  @override
  Future<int> getProfileViewCount(String userId) async => 0;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final saved = _preferences.getString(_storageKey);
    if (saved != null) {
      final profile = _profileFromJson(saved);
      final normalized = _profileToJson(profile);
      if (normalized != saved) {
        await _preferences.setString(_storageKey, normalized);
      }
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
  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) async {
    if (isProfileSaveNoOp(
      currentProfile: currentProfile,
      displayName: displayName,
      birthDate: birthDate,
      gender: gender,
      username: username,
      bio: bio,
      photos: photos,
    )) {
      return currentProfile;
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final normalizedPhotos = [
      for (var index = 0; index < photos.length; index++)
        photos[index].copyWith(position: index),
    ];
    final primary = normalizedPhotos.firstOrNull;
    final profile = currentProfile.copyWith(
      displayName: displayName.trim(),
      birthDate: birthDate,
      username: username.trim().toLowerCase(),
      gender: gender,
      bio: bio.trim(),
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
    return _preferences.setString(_storageKey, _profileToJson(profile));
  }

  String _profileToJson(UserProfile profile) {
    return jsonEncode({
      'id': profile.id,
      'username': profile.username,
      'display_name': profile.displayName,
      'birth_date': profile.birthDate?.toIso8601String(),
      'avatar_url': profile.avatarUrl,
      'avatar_storage_path': profile.avatarStoragePath,
      // photos[0] is the source of truth; keep this only for legacy profiles.
      'avatar_bytes': profile.photos.isNotEmpty || profile.avatarBytes == null
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
              'bytes': photo.bytes == null ? null : base64Encode(photo.bytes!),
              'updated_at': photo.updatedAt?.toIso8601String(),
            },
          )
          .toList(growable: false),
    });
  }

  UserProfile _profileFromJson(String value) {
    final map = Map<String, dynamic>.from(jsonDecode(value) as Map);
    final encodedAvatar = map.remove('avatar_bytes') as String?;
    final photoMaps = (map.remove('photos') as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final parsed = UserProfile.fromMap(map).copyWith(
      avatarBytes: encodedAvatar == null ? null : base64Decode(encodedAvatar),
      photos: [
        for (var index = 0; index < photoMaps.length; index++)
          ProfilePhoto(
            position: index,
            avatarUrl: photoMaps[index]['avatar_url'] as String?,
            storagePath: photoMaps[index]['storage_path'] as String?,
            bytes: photoMaps[index]['bytes'] == null
                ? null
                : base64Decode(photoMaps[index]['bytes'] as String),
            updatedAt: DateTime.tryParse(
              photoMaps[index]['updated_at'] as String? ?? '',
            ),
          ),
      ],
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
