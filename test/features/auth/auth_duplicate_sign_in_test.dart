import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';

final class _ControllableAuthRepository implements IAuthRepository {
  AuthSession? session;
  int signInCalls = 0;
  int cancelCalls = 0;
  bool callbackProcessing = false;

  final _sessions = StreamController<AuthSession?>.broadcast();

  @override
  AuthSession? get currentSession => session;

  @override
  bool get isSignInCallbackProcessing => callbackProcessing;

  @override
  Stream<AuthSession?> observeSession() => _sessions.stream;

  @override
  Future<AuthAccountAccess> getAccountAccess() async =>
      const AuthAccountAccess(isBanned: false);

  @override
  Future<AuthAccountAccess?> getCachedAccountAccess(String userId) async => null;

  @override
  Future<void> cacheAccountAccess(
    String userId,
    AuthAccountAccess access,
  ) async {}

  @override
  Future<void> signInWithYandex() async {
    signInCalls++;
  }

  @override
  Future<void> cancelPendingSignIn() async {
    cancelCalls++;
  }

  @override
  Future<DateTime?> requestAccountDeletion(AccountDeletionSurvey survey) async => null;

  @override
  Future<void> restoreAccountDeletion() async {}

  @override
  Future<void> signOut({bool preserveAccountAccess = false}) async {
    session = null;
    _sessions.add(null);
  }

  void emitSession(AuthSession value) {
    session = value;
    _sessions.add(value);
  }

  void emitError() {
    _sessions.addError(StateError('stale OAuth callback'));
  }

  Future<void> close() => _sessions.close();
}

final class _ImmediateProfileRepository implements IProfileRepository {
  @override
  Future<UserProfile?> getCachedProfile(String userId) async => null;

  @override
  Future<String?> resolveSharedProfileUsername(String username) async => null;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    final acceptedAt = DateTime.utc(2026, 1, 1);
    return UserProfile(
      id: session.userId,
      username: 'test_user',
      displayName: 'Test User',
      birthDate: DateTime.utc(2000, 1, 1),
      onboardingCompleted: true,
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
    );
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
  }) async => currentProfile;
}

void main() {
  late _ControllableAuthRepository authRepository;
  late AuthBloc bloc;

  setUp(() {
    authRepository = _ControllableAuthRepository();
    bloc = AuthBloc(
      authRepository: authRepository,
      profileRepository: _ImmediateProfileRepository(),
    );
  });

  tearDown(() async {
    await bloc.close();
    await authRepository.close();
  });

  Future<void> startUnauthenticated() async {
    final unauthenticated = bloc.stream.firstWhere(
      (state) => state.status == AuthStatus.unauthenticated,
    );
    bloc.add(const AuthStarted());
    await unauthenticated;
  }

  Future<void> requestSignIn() async {
    final pending = bloc.stream.firstWhere((state) => state.isSubmitting);
    bloc.add(const YandexSignInRequested());
    await pending;
  }

  test(
    'keeps OAuth pending and ignores an accidental second request',
    () async {
      await startUnauthenticated();

      await requestSignIn();

      bloc.add(const YandexSignInRequested());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isSubmitting, isTrue);
      expect(authRepository.signInCalls, 1);
    },
  );

  test('allows an explicit cancel followed by a fresh request', () async {
    await startUnauthenticated();

    await requestSignIn();

    final cancelled = bloc.stream.firstWhere((state) => !state.isSubmitting);
    bloc.add(const AuthSignInCancelled());
    await cancelled;

    await requestSignIn();

    expect(authRepository.signInCalls, 2);
    expect(authRepository.cancelCalls, 1);
  });

  test(
    'browser return unlocks the UI without invalidating the attempt',
    () async {
      await startUnauthenticated();
      await requestSignIn();

      final returned = bloc.stream.firstWhere((state) => !state.isSubmitting);
      bloc.add(const AuthSignInBrowserReturned());
      await returned;

      expect(authRepository.cancelCalls, 0);
      expect(bloc.state.failure, isNull);
    },
  );

  test(
    'browser return keeps waiting while callback is being exchanged',
    () async {
      await startUnauthenticated();
      await requestSignIn();
      authRepository.callbackProcessing = true;

      bloc.add(const AuthSignInBrowserReturned());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isSubmitting, isTrue);
      expect(bloc.state.isCompletingSignIn, isTrue);
      expect(authRepository.cancelCalls, 0);
    },
  );

  test(
    'manual cancel cannot replace a callback already being exchanged',
    () async {
      await startUnauthenticated();
      await requestSignIn();
      authRepository.callbackProcessing = true;

      bloc.add(const AuthSignInCancelled());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isSubmitting, isTrue);
      expect(bloc.state.isCompletingSignIn, isFalse);
      expect(authRepository.cancelCalls, 0);
    },
  );

  test('keeps a successful session after a stale callback error', () async {
    await startUnauthenticated();
    await requestSignIn();

    const session = AuthSession(userId: 'second-oauth-account');
    final authenticated = bloc.stream.firstWhere(
      (state) => state.status == AuthStatus.authenticated,
    );
    authRepository.emitSession(session);
    await authenticated;

    authRepository.emitError();
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.status, AuthStatus.authenticated);
    expect(bloc.state.session, session);
    expect(bloc.state.failure, isNull);
    expect(bloc.state.isSubmitting, isFalse);
  });

  test(
    'recovers the SDK session when its event is preceded by an error',
    () async {
      await startUnauthenticated();

      const session = AuthSession(userId: 'already-persisted-account');
      authRepository.session = session;
      final authenticated = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.authenticated,
      );
      authRepository.emitError();
      await authenticated;

      expect(bloc.state.session, session);
      expect(bloc.state.failure, isNull);
    },
  );

  test('reports a sign-in failure when no SDK session exists', () async {
    await startUnauthenticated();
    await requestSignIn();

    final failure = bloc.stream.firstWhere(
      (state) => state.failure == AuthFailure.signIn,
    );
    authRepository.emitError();
    final state = await failure;

    expect(state.status, AuthStatus.unauthenticated);
    expect(state.session, isNull);
    expect(state.isSubmitting, isFalse);
  });

  testWidgets('shows an explicit cancel action while OAuth is pending', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await startUnauthenticated();
      await requestSignIn();
    });
    expect(bloc.state.isSubmitting, isTrue);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WelcomePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('отмена'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('отмена'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('отмена'));
    await tester.pump();

    expect(bloc.state.isSubmitting, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('disables cancellation after the callback exchange starts', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await startUnauthenticated();
      await requestSignIn();
      authRepository.callbackProcessing = true;
      final completing = bloc.stream.firstWhere(
        (state) => state.isCompletingSignIn,
      );
      bloc.add(const AuthSignInBrowserReturned());
      await completing;
    });

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WelcomePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Отмена'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets(
    'portrait layout does not overlap and unlocks after browser return',
    (tester) async {
      tester.view.physicalSize = const Size(412, 732);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await startUnauthenticated();
        await requestSignIn();
      });
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WelcomePage(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final cancelRect = tester.getRect(find.text('отмена'));
      final consentRect = tester.getRect(
        find.textContaining('При входе или регистрации', findRichText: true),
      );
      expect(cancelRect.bottom, lessThan(consentRect.top));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 701));
      await tester.pump();

      expect(bloc.state.isSubmitting, isFalse);
      expect(authRepository.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
