import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

enum AuthStatus {
  initial,
  loading,
  unauthenticated,
  profileIncomplete,
  authenticated,
  banned,
  deletionPending,
  failure,
}

enum AuthFailure {
  signIn,
  session,
  profileLoad,
  profileSave,
  usernameTaken,
  invalidUsername,
  invalidDisplayName,
  accountDeletion,
  accountRestore,
  signOut,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.session,
    this.profile,
    this.failure,
    this.bannedUsername,
    this.bannedSupportEmail,
    this.isDeletionExpired = false,
    this.deletionScheduledFor,
    this.isSubmitting = false,
    this.isCompletingSignIn = false,
  });

  final AuthStatus status;
  final AuthSession? session;
  final UserProfile? profile;
  final AuthFailure? failure;
  final String? bannedUsername;
  final String? bannedSupportEmail;
  final bool isDeletionExpired;
  final DateTime? deletionScheduledFor;
  final bool isSubmitting;
  final bool isCompletingSignIn;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    UserProfile? profile,
    AuthFailure? failure,
    String? bannedUsername,
    String? bannedSupportEmail,
    bool? isDeletionExpired,
    DateTime? deletionScheduledFor,
    bool? isSubmitting,
    bool? isCompletingSignIn,
    bool clearSession = false,
    bool clearProfile = false,
    bool clearFailure = false,
    bool clearBannedUsername = false,
    bool clearBannedSupportEmail = false,
    bool clearDeletionExpired = false,
    bool clearDeletionScheduledFor = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: clearSession ? null : session ?? this.session,
      profile: clearProfile ? null : profile ?? this.profile,
      failure: clearFailure ? null : failure ?? this.failure,
      bannedUsername: clearBannedUsername
          ? null
          : bannedUsername ?? this.bannedUsername,
      bannedSupportEmail: clearBannedSupportEmail
          ? null
          : bannedSupportEmail ?? this.bannedSupportEmail,
      isDeletionExpired: clearDeletionExpired
          ? false
          : isDeletionExpired ?? this.isDeletionExpired,
      deletionScheduledFor: clearDeletionScheduledFor
          ? null
          : deletionScheduledFor ?? this.deletionScheduledFor,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isCompletingSignIn: isCompletingSignIn ?? this.isCompletingSignIn,
    );
  }

  @override
  List<Object?> get props => [
    status,
    session,
    profile,
    failure,
    bannedUsername,
    bannedSupportEmail,
    isDeletionExpired,
    deletionScheduledFor,
    isSubmitting,
    isCompletingSignIn,
  ];
}
