import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.onboardingCompleted,
    this.birthDate,
    this.avatarUrl,
    this.termsAcceptedAt,
    this.privacyAcceptedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: map['username'] as String,
      displayName: map['display_name'] as String? ?? '',
      birthDate: DateTime.tryParse(map['birth_date'] as String? ?? ''),
      avatarUrl: map['avatar_url'] as String?,
      onboardingCompleted: map['onboarding_completed'] as bool? ?? false,
      termsAcceptedAt: DateTime.tryParse(
        map['terms_accepted_at'] as String? ?? '',
      ),
      privacyAcceptedAt: DateTime.tryParse(
        map['privacy_accepted_at'] as String? ?? '',
      ),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final DateTime? birthDate;
  final String? avatarUrl;
  final bool onboardingCompleted;
  final DateTime? termsAcceptedAt;
  final DateTime? privacyAcceptedAt;

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
    bool? onboardingCompleted,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    displayName,
    birthDate,
    avatarUrl,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
  ];
}
