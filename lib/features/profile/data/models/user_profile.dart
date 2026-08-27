import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/models/profile_photo.dart';

enum ProfileGender {
  male,
  female,
  unspecified;

  String get databaseValue => name;

  static ProfileGender fromDatabaseValue(String? value) {
    return ProfileGender.values.firstWhere(
      (gender) => gender.databaseValue == value,
      orElse: () => ProfileGender.unspecified,
    );
  }
}

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.onboardingCompleted,
    this.birthDate,
    this.avatarUrl,
    this.avatarStoragePath,
    this.avatarBytes,
    this.avatarUpdatedAt,
    this.photos = const [],
    this.gender = ProfileGender.unspecified,
    this.bio = '',
    this.termsAcceptedAt,
    this.privacyAcceptedAt,
    this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: map['username'] as String,
      displayName: map['display_name'] as String? ?? '',
      birthDate: DateTime.tryParse(map['birth_date'] as String? ?? ''),
      avatarUrl: map['avatar_url'] as String?,
      avatarStoragePath: map['avatar_storage_path'] as String?,
      avatarUpdatedAt: DateTime.tryParse(
        map['avatar_updated_at'] as String? ?? '',
      ),
      gender: ProfileGender.fromDatabaseValue(map['gender'] as String?),
      bio: map['bio'] as String? ?? '',
      onboardingCompleted: map['onboarding_completed'] as bool? ?? false,
      termsAcceptedAt: DateTime.tryParse(
        map['terms_accepted_at'] as String? ?? '',
      ),
      privacyAcceptedAt: DateTime.tryParse(
        map['privacy_accepted_at'] as String? ?? '',
      ),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final DateTime? birthDate;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final Uint8List? avatarBytes;
  final DateTime? avatarUpdatedAt;
  final List<ProfilePhoto> photos;
  final ProfileGender gender;
  final String bio;
  final bool onboardingCompleted;
  final DateTime? termsAcceptedAt;
  final DateTime? privacyAcceptedAt;
  final DateTime? createdAt;

  List<ProfilePhoto> get effectivePhotos {
    if (photos.isNotEmpty) return photos;
    if (avatarUrl == null && avatarStoragePath == null && avatarBytes == null) {
      return const [];
    }
    return [
      ProfilePhoto(
        position: 0,
        avatarUrl: avatarStoragePath == null ? avatarUrl : null,
        storagePath: avatarStoragePath,
        bytes: avatarBytes,
        updatedAt: avatarUpdatedAt,
      ),
    ];
  }

  ProfilePhoto? get primaryPhoto => effectivePhotos.firstOrNull;

  bool get hasRequiredData =>
      displayName.trim().isNotEmpty &&
      birthDate != null &&
      termsAcceptedAt != null &&
      privacyAcceptedAt != null;

  UserProfile copyWith({
    String? username,
    String? displayName,
    DateTime? birthDate,
    String? avatarUrl,
    String? avatarStoragePath,
    Uint8List? avatarBytes,
    DateTime? avatarUpdatedAt,
    List<ProfilePhoto>? photos,
    ProfileGender? gender,
    String? bio,
    bool? onboardingCompleted,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
    DateTime? createdAt,
    bool clearAvatarUrl = false,
    bool clearAvatarStoragePath = false,
    bool clearAvatarBytes = false,
    bool clearAvatarUpdatedAt = false,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      avatarStoragePath: clearAvatarStoragePath
          ? null
          : avatarStoragePath ?? this.avatarStoragePath,
      avatarBytes: clearAvatarBytes ? null : avatarBytes ?? this.avatarBytes,
      avatarUpdatedAt: clearAvatarUpdatedAt
          ? null
          : avatarUpdatedAt ?? this.avatarUpdatedAt,
      photos: photos ?? this.photos,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    birthDate,
    avatarUrl,
    avatarStoragePath,
    avatarBytes,
    avatarUpdatedAt,
    photos,
    gender,
    bio,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
    createdAt,
  ];
}
