import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => const [];
}

final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

final class YandexSignInRequested extends AuthEvent {
  const YandexSignInRequested();
}

final class AuthSignInCancelled extends AuthEvent {
  const AuthSignInCancelled();
}

final class AuthSessionStreamFailed extends AuthEvent {
  const AuthSessionStreamFailed();
}

final class AuthSessionChanged extends AuthEvent {
  const AuthSessionChanged(this.session);

  final AuthSession? session;

  @override
  List<Object?> get props => [session];
}

final class AuthProfileSubmitted extends AuthEvent {
  const AuthProfileSubmitted({
    required this.displayName,
    required this.birthDate,
    required this.gender,
    this.username,
    this.bio,
    this.avatarBytes,
    this.photos,
    this.removeAvatar = false,
  });

  final String displayName;
  final DateTime birthDate;
  final ProfileGender gender;
  final String? username;
  final String? bio;
  final Uint8List? avatarBytes;
  final List<ProfilePhoto>? photos;
  final bool removeAvatar;

  @override
  List<Object?> get props => [
    displayName,
    birthDate,
    gender,
    username,
    bio,
    avatarBytes,
    photos,
    removeAvatar,
  ];
}

final class AuthProfileUpdated extends AuthEvent {
  const AuthProfileUpdated(this.profile);

  final UserProfile profile;

  @override
  List<Object?> get props => [profile];
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

final class AuthRetryRequested extends AuthEvent {
  const AuthRetryRequested();
}

final class AuthFailureCleared extends AuthEvent {
  const AuthFailureCleared();
}
