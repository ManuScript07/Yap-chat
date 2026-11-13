import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthBloc', () {
    late AuthBloc bloc;
    late MockAuthRepository authRepository;
    late List<String> clearedUserIds;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      clearedUserIds = [];
      authRepository = MockAuthRepository(preferences: preferences);
      bloc = AuthBloc(
        authRepository: authRepository,
        profileRepository: MockProfileRepository(preferences: preferences),
        clearUserCache: (userId) async => clearedUserIds.add(userId),
      );
    });

    tearDown(() => bloc.close());

    test('completes the first sign-in flow and signs out', () async {
      final states = <AuthStatus>[];
      final stateSubscription = bloc.stream.listen(
        (state) => states.add(state.status),
      );
      addTearDown(stateSubscription.cancel);

      final unauthenticated = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );
      bloc.add(const AuthStarted());
      await unauthenticated.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw StateError('Unauthenticated not emitted: $states'),
      );

      final profileIncomplete = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.profileIncomplete,
      );
      bloc.add(const YandexSignInRequested());
      final incompleteState = await profileIncomplete.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw StateError('Profile incomplete not emitted: $states'),
      );
      expect(incompleteState.profile?.username, matches(r'^[a-z0-9]{8}$'));
      final termsAcceptedAt = incompleteState.profile?.termsAcceptedAt;
      final privacyAcceptedAt = incompleteState.profile?.privacyAcceptedAt;
      expect(termsAcceptedAt, isNotNull);
      expect(privacyAcceptedAt, isNotNull);

      final authenticated = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.authenticated,
      );
      bloc.add(
        AuthProfileSubmitted(
          displayName: 'Иван',
          birthDate: DateTime(2000, 1, 1),
          gender: ProfileGender.unspecified,
        ),
      );
      final authenticatedState = await authenticated.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Authenticated not emitted: $states'),
      );
      expect(authenticatedState.profile?.onboardingCompleted, isTrue);
      expect(authenticatedState.profile?.termsAcceptedAt, termsAcceptedAt);
      expect(authenticatedState.profile?.privacyAcceptedAt, privacyAcceptedAt);

      final editedProfile = authenticatedState.profile!.copyWith(
        username: 'edited_user',
      );
      final profileUpdated = bloc.stream.firstWhere(
        (state) => state.profile?.username == 'edited_user',
      );
      bloc.add(AuthProfileUpdated(editedProfile));
      final editedState = await profileUpdated;
      expect(editedState.status, AuthStatus.authenticated);
      expect(editedState.isSubmitting, isFalse);

      final signedOut = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );
      bloc.add(const AuthSignOutRequested());
      await signedOut.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Signed out not emitted: $states'),
      );
      expect(bloc.state.session, isNull);
      expect(clearedUserIds, hasLength(1));

      final reauthenticated = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.authenticated,
      );
      bloc.add(const YandexSignInRequested());
      final reauthenticatedState = await reauthenticated.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Authenticated not emitted: $states'),
      );
      expect(reauthenticatedState.profile?.termsAcceptedAt, termsAcceptedAt);
      expect(
        reauthenticatedState.profile?.privacyAcceptedAt,
        privacyAcceptedAt,
      );
    });

    test('does not expose welcome before account cleanup finishes', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final authRepository = MockAuthRepository(preferences: preferences);
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final sessionController = AccountSessionController();
      final delayedBloc = AuthBloc(
        authRepository: authRepository,
        profileRepository: MockProfileRepository(preferences: preferences),
        accountSessionController: sessionController,
        markUserCleanupPending: (_) async {},
        clearUserCache: (_) async {
          cleanupStarted.complete();
          await releaseCleanup.future;
        },
      );
      addTearDown(delayedBloc.close);

      final welcome = delayedBloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );
      delayedBloc.add(const AuthStarted());
      await welcome;

      final signedIn = delayedBloc.stream.firstWhere(
        (state) => state.status == AuthStatus.profileIncomplete,
      );
      delayedBloc.add(const YandexSignInRequested());
      await signedIn;
      expect(sessionController.userId, MockAuthRepository.mockUserId);

      final signedOut = delayedBloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );
      delayedBloc.add(const AuthSignOutRequested());
      await cleanupStarted.future;

      expect(delayedBloc.state.status, AuthStatus.loading);
      expect(delayedBloc.state.isSubmitting, isTrue);
      expect(sessionController.userId, isNull);

      releaseCleanup.complete();
      await signedOut;
      expect(delayedBloc.state.isSubmitting, isFalse);
    });

    test(
      'keeps the deletion marker through sign-out and clears it on restore',
      () async {
        final signedOut = bloc.stream.firstWhere(
          (state) => state.status == AuthStatus.unauthenticated,
        );
        bloc.add(const AuthStarted());
        await signedOut;

        final signedIn = bloc.stream.firstWhere(
          (state) =>
              state.session?.userId == MockAuthRepository.mockUserId &&
              state.status == AuthStatus.profileIncomplete &&
              !state.isSubmitting,
        );
        bloc.add(const YandexSignInRequested());
        await signedIn;

        final deletionSignedOut = bloc.stream.firstWhere(
          (state) => state.status == AuthStatus.unauthenticated,
        );
        bloc.add(
          const AuthAccountDeletionRequested(
            AccountDeletionSurvey(reasons: [AccountDeletionReason.other]),
          ),
        );
        await deletionSignedOut;
        expect(
          (await authRepository.getCachedAccountAccess(
            MockAuthRepository.mockUserId,
          ))?.isDeletionPending,
          isTrue,
        );

        final deletionPending = bloc.stream.firstWhere(
          (state) => state.status == AuthStatus.deletionPending,
        );
        bloc.add(const YandexSignInRequested());
        await deletionPending;

        final restored = bloc.stream.firstWhere(
          (state) =>
              state.status == AuthStatus.profileIncomplete &&
              !state.isSubmitting,
        );
        bloc.add(const AuthAccountRestoreRequested());
        await restored;
        expect(
          await authRepository.getCachedAccountAccess(
            MockAuthRepository.mockUserId,
          ),
          isNull,
        );
      },
    );

    test(
      'loads B instead of retaining A profile if auth changes on logout',
      () async {
        final authRepository = _SwitchingOnSignOutAuthRepository();
        final switchingBloc = AuthBloc(
          authRepository: authRepository,
          profileRepository: _AccountProfileRepository(),
          accountSessionController: AccountSessionController(
            initialUserId: 'account-a',
          ),
          markUserCleanupPending: (_) async {},
          clearUserCache: (_) async {},
        );
        addTearDown(switchingBloc.close);
        addTearDown(authRepository.close);

        final accountA = switchingBloc.stream.firstWhere(
          (state) =>
              state.session?.userId == 'account-a' && state.profile != null,
        );
        switchingBloc.add(const AuthStarted());
        await accountA;

        final loadingAccountB = switchingBloc.stream.firstWhere(
          (state) => state.session?.userId == 'account-b',
        );
        final accountB = switchingBloc.stream.firstWhere(
          (state) =>
              state.session?.userId == 'account-b' &&
              state.profile?.id == 'account-b',
        );
        switchingBloc.add(const AuthSignOutRequested());
        expect((await loadingAccountB).profile, isNull);
        final state = await accountB;

        expect(state.profile?.id, 'account-b');
        expect(state.profile?.id, isNot('account-a'));
      },
    );
  });
}

class _AccountProfileRepository implements IProfileRepository {
  @override
  Future<UserProfile?> getCachedProfile(String userId) async => null;

  @override
  Future<String?> resolveSharedProfileUsername(String username) async => null;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    return UserProfile(
      id: session.userId,
      username: 'user_${session.userId}',
      displayName: session.userId,
      onboardingCompleted: false,
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

class _SwitchingOnSignOutAuthRepository implements IAuthRepository {
  final StreamController<AuthSession?> _sessions =
      StreamController<AuthSession?>.broadcast();
  AuthSession? _session = const AuthSession(userId: 'account-a');

  @override
  AuthSession? get currentSession => _session;

  @override
  bool get isSignInCallbackProcessing => false;

  @override
  Stream<AuthSession?> observeSession() => _sessions.stream;

  @override
  Future<AuthAccountAccess> getAccountAccess() async =>
      const AuthAccountAccess(isBanned: false);

  @override
  Future<AuthAccountAccess?> getCachedAccountAccess(String userId) async =>
      null;

  @override
  Future<void> cacheAccountAccess(
    String userId,
    AuthAccountAccess access,
  ) async {}

  @override
  Future<void> cancelPendingSignIn() async {}

  @override
  Future<void> signInWithYandex() async {}

  @override
  Future<DateTime?> requestAccountDeletion(AccountDeletionSurvey survey) async => null;

  @override
  Future<void> restoreAccountDeletion() async {}

  @override
  Future<void> signOut({bool preserveAccountAccess = false}) async {
    _session = const AuthSession(userId: 'account-b');
    _sessions.add(_session);
  }

  Future<void> close() => _sessions.close();
}
