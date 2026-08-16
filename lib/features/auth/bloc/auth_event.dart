import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/auth/data/data.dart';

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
    required this.acceptedTerms,
    this.username,
    this.avatarUrl,
  });

  final String displayName;
  final DateTime birthDate;
  final bool acceptedTerms;
  final String? username;
  final String? avatarUrl;

  @override
  List<Object?> get props => [
    displayName,
    birthDate,
    acceptedTerms,
    username,
    avatarUrl,
  ];
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
