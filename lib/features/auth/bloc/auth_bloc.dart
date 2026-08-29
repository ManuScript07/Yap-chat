import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/auth/bloc/auth_event.dart';
import 'package:yap_chat/features/auth/bloc/auth_state.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required IAuthRepository authRepository,
    required IProfileRepository profileRepository,
    Future<void> Function(String userId)? clearUserCache,
    Future<void> Function()? beforeSignOut,
  }) : _authRepository = authRepository,
       _profileRepository = profileRepository,
       _clearUserCache = clearUserCache,
       _beforeSignOut = beforeSignOut,
       super(const AuthState()) {
    on<AuthStarted>(_onStarted, transformer: restartable());
    on<YandexSignInRequested>(
      _onYandexSignInRequested,
      transformer: droppable(),
    );
    on<AuthSignInCancelled>(_onSignInCancelled);
    on<AuthSignInBrowserReturned>(_onSignInBrowserReturned);
    on<AuthSessionStreamFailed>(_onSessionStreamFailed);
    on<AuthSessionChanged>(_onSessionChanged, transformer: restartable());
    on<AuthProfileSubmitted>(_onProfileSubmitted, transformer: droppable());
    on<AuthProfileUpdated>(_onProfileUpdated);
    on<AuthSignOutRequested>(_onSignOutRequested, transformer: droppable());
    on<AuthRetryRequested>(_onRetryRequested);
    on<AuthFailureCleared>(_onFailureCleared);
  }

  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

  final IAuthRepository _authRepository;
  final IProfileRepository _profileRepository;
  final Future<void> Function(String userId)? _clearUserCache;
  final Future<void> Function()? _beforeSignOut;
  StreamSubscription<AuthSession?>? _sessionSubscription;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(
      state.copyWith(
        status: AuthStatus.loading,
        isSubmitting: false,
        isCompletingSignIn: false,
        clearFailure: true,
      ),
    );
    await _sessionSubscription?.cancel();
    _sessionSubscription = _authRepository.observeSession().listen(
      (session) => add(AuthSessionChanged(session)),
      onError: (_, _) => add(const AuthSessionStreamFailed()),
    );
    add(AuthSessionChanged(_authRepository.currentSession));
  }

  Future<void> _onYandexSignInRequested(
    YandexSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state.isSubmitting) return;

    emit(
      state.copyWith(
        isSubmitting: true,
        isCompletingSignIn: false,
        clearFailure: true,
      ),
    );
    try {
      await _authRepository.signInWithYandex();
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          failure: AuthFailure.signIn,
          isSubmitting: false,
          isCompletingSignIn: false,
        ),
      );
    }
  }

  Future<void> _onSignInCancelled(
    AuthSignInCancelled event,
    Emitter<AuthState> emit,
  ) async {
    if (!state.isSubmitting ||
        state.session != null ||
        state.isCompletingSignIn ||
        _authRepository.isSignInCallbackProcessing) {
      return;
    }
    emit(
      state.copyWith(
        isSubmitting: false,
        isCompletingSignIn: false,
        clearFailure: true,
      ),
    );
    await _authRepository.cancelPendingSignIn();
  }

  void _onSignInBrowserReturned(
    AuthSignInBrowserReturned event,
    Emitter<AuthState> emit,
  ) {
    if (!state.isSubmitting || state.session != null) {
      return;
    }

    if (_authRepository.isSignInCallbackProcessing) {
      emit(state.copyWith(isCompletingSignIn: true));
      return;
    }

    emit(
      state.copyWith(
        isSubmitting: false,
        isCompletingSignIn: false,
        clearFailure: true,
      ),
    );
  }

  void _onSessionStreamFailed(
    AuthSessionStreamFailed event,
    Emitter<AuthState> emit,
  ) {
    final currentSession = _authRepository.currentSession;
    if (currentSession != null) {
      if (state.session != currentSession) {
        add(AuthSessionChanged(currentSession));
      } else if (state.isSubmitting) {
        emit(state.copyWith(isSubmitting: false, isCompletingSignIn: false));
      }
      return;
    }

    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        failure: AuthFailure.signIn,
        isSubmitting: false,
        isCompletingSignIn: false,
        clearSession: true,
        clearProfile: true,
      ),
    );
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
          isCompletingSignIn: false,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: AuthStatus.loading,
        session: session,
        isSubmitting: false,
        isCompletingSignIn: false,
        clearFailure: true,
      ),
    );
    UserProfile? cachedProfile;
    try {
      cachedProfile = await _profileRepository.getCachedProfile(session.userId);
      if (cachedProfile != null) {
        emit(
          state.copyWith(
            status: _statusForProfile(cachedProfile),
            session: session,
            profile: cachedProfile,
            isSubmitting: false,
          ),
        );
      }
    } catch (_) {
      // Повреждённый кеш не должен блокировать загрузку актуального профиля.
    }

    try {
      final profile = await _profileRepository.getOrCreateProfile(session);
      emit(
        state.copyWith(
          status: _statusForProfile(profile),
          session: session,
          profile: profile,
          isSubmitting: false,
        ),
      );
    } catch (_) {
      if (cachedProfile != null) {
        emit(
          state.copyWith(
            status: _statusForProfile(cachedProfile),
            session: session,
            profile: cachedProfile,
            isSubmitting: false,
          ),
        );
        return;
      }
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
    final currentProfile = state.profile;
    if (session == null || currentProfile == null) return;

    final displayName = event.displayName.trim();
    if (displayName.length < 2 || displayName.length > 30) {
      emit(state.copyWith(failure: AuthFailure.invalidDisplayName));
      return;
    }

    final username = event.username?.trim().toLowerCase();
    if (username != null &&
        username.isNotEmpty &&
        !_usernamePattern.hasMatch(username)) {
      emit(state.copyWith(failure: AuthFailure.invalidUsername));
      return;
    }

    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    try {
      final photos = event.photos != null
          ? List<ProfilePhoto>.unmodifiable(event.photos!)
          : event.avatarBytes != null
          ? [ProfilePhoto(position: 0, bytes: event.avatarBytes)]
          : event.removeAvatar
          ? const <ProfilePhoto>[]
          : currentProfile.effectivePhotos;
      final profile = await _profileRepository.saveOwnProfile(
        currentProfile: currentProfile,
        displayName: displayName,
        birthDate: event.birthDate,
        gender: event.gender,
        username: username?.isNotEmpty == true
            ? username!
            : currentProfile.username,
        bio: event.bio ?? '',
        photos: photos,
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

  void _onProfileUpdated(AuthProfileUpdated event, Emitter<AuthState> emit) {
    if (state.session?.userId != event.profile.id) return;
    emit(
      state.copyWith(
        status: AuthStatus.authenticated,
        profile: event.profile,
        clearFailure: true,
      ),
    );
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final userId = state.session?.userId;
    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    try {
      try {
        await _beforeSignOut?.call();
      } catch (_) {
        // Ошибка отписки от push не должна блокировать выход из аккаунта.
      }
      await _authRepository.signOut();
      if (userId != null) {
        try {
          await _clearUserCache?.call(userId);
        } catch (_) {
          // Выход не должен отменяться из-за ошибки очистки локального кеша.
        }
      }
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

  AuthStatus _statusForProfile(UserProfile profile) {
    return profile.onboardingCompleted && profile.hasRequiredData
        ? AuthStatus.authenticated
        : AuthStatus.profileIncomplete;
  }

  @override
  Future<void> close() async {
    await _sessionSubscription?.cancel();
    return super.close();
  }
}
