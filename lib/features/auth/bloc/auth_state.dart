import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

enum AuthStatus {
  initial,
  loading,
  unauthenticated,
  profileIncomplete,
  authenticated,
  failure,
}

enum AuthFailure {
  signIn,
  session,
  profileLoad,
  profileSave,
  usernameTaken,
  invalidUsername,
  signOut,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.session,
    this.profile,
    this.failure,
    this.isSubmitting = false,
  });

  final AuthStatus status;
  final AuthSession? session;
  final UserProfile? profile;
  final AuthFailure? failure;
  final bool isSubmitting;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    UserProfile? profile,
    AuthFailure? failure,
    bool? isSubmitting,
    bool clearSession = false,
    bool clearProfile = false,
    bool clearFailure = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: clearSession ? null : session ?? this.session,
      profile: clearProfile ? null : profile ?? this.profile,
      failure: clearFailure ? null : failure ?? this.failure,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  @override
  List<Object?> get props => [status, session, profile, failure, isSubmitting];
}
