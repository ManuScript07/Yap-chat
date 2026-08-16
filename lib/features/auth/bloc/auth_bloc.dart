import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/auth/bloc/auth_event.dart';
import 'package:yap_chat/features/auth/bloc/auth_state.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required IAuthRepository authRepository,
    required IProfileRepository profileRepository,
  }) : _authRepository = authRepository,
       _profileRepository = profileRepository,
       super(const AuthState()) {
    on<AuthStarted>(_onStarted, transformer: restartable());
    on<YandexSignInRequested>(
      _onYandexSignInRequested,
      transformer: droppable(),
    );
    on<AuthSessionChanged>(_onSessionChanged, transformer: restartable());
    on<AuthProfileSubmitted>(_onProfileSubmitted, transformer: droppable());
    on<AuthSignOutRequested>(_onSignOutRequested, transformer: droppable());
    on<AuthRetryRequested>(_onRetryRequested);
    on<AuthFailureCleared>(_onFailureCleared);
  }

  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

  final IAuthRepository _authRepository;
  final IProfileRepository _profileRepository;
  StreamSubscription<AuthSession?>? _sessionSubscription;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.loading, clearFailure: true));
    await _sessionSubscription?.cancel();
    _sessionSubscription = _authRepository.observeSession().listen(
      (session) => add(AuthSessionChanged(session)),
      onError: (_, _) => add(const AuthSessionChanged(null)),
    );
    add(AuthSessionChanged(_authRepository.currentSession));
  }

  Future<void> _onYandexSignInRequested(
    YandexSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    try {
      await _authRepository.signInWithYandex();
      emit(state.copyWith(isSubmitting: false));
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          failure: AuthFailure.signIn,
          isSubmitting: false,
        ),
      );
    }
  }

  Future<void> _onSessionChanged(
    AuthSessionChanged event,
    Emitter<AuthState> emit,
  ) async {
    final session = event.session;
    if (session == null) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearSession: true,
          clearProfile: true,
          isSubmitting: false,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: AuthStatus.loading,
        session: session,
        clearFailure: true,
      ),
    );
    try {
      final profile = await _profileRepository.getOrCreateProfile(session);
      final isComplete = profile.onboardingCompleted && profile.hasRequiredData;
      emit(
        state.copyWith(
          status: isComplete
              ? AuthStatus.authenticated
              : AuthStatus.profileIncomplete,
          session: session,
          profile: profile,
          isSubmitting: false,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          session: session,
          failure: AuthFailure.profileLoad,
          isSubmitting: false,
        ),
      );
    }
  }

  Future<void> _onProfileSubmitted(
    AuthProfileSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final session = state.session;
    if (session == null || event.displayName.trim().isEmpty) return;

    final username = event.username?.trim().toLowerCase();
    if (username != null &&
        username.isNotEmpty &&
        !_usernamePattern.hasMatch(username)) {
      emit(state.copyWith(failure: AuthFailure.invalidUsername));
      return;
    }

    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    try {
      final profile = await _profileRepository.completeProfile(
        userId: session.userId,
        displayName: event.displayName,
        birthDate: event.birthDate,
        acceptedTerms: event.acceptedTerms,
        username: username,
        avatarUrl: event.avatarUrl,
      );
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          profile: profile,
          isSubmitting: false,
        ),
      );
    } on UsernameAlreadyTakenException {
      emit(
        state.copyWith(failure: AuthFailure.usernameTaken, isSubmitting: false),
      );
    } catch (_) {
      emit(
        state.copyWith(failure: AuthFailure.profileSave, isSubmitting: false),
      );
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    try {
      await _authRepository.signOut();
    } catch (_) {
      emit(state.copyWith(failure: AuthFailure.signOut, isSubmitting: false));
    }
  }

  void _onRetryRequested(AuthRetryRequested event, Emitter<AuthState> emit) {
    add(const AuthStarted());
  }

  void _onFailureCleared(AuthFailureCleared event, Emitter<AuthState> emit) {
    emit(state.copyWith(clearFailure: true));
  }

  @override
  Future<void> close() async {
    await _sessionSubscription?.cancel();
    return super.close();
  }
}
