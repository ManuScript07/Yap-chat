import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthBloc', () {
    late AuthBloc bloc;
    late List<String> clearedUserIds;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      clearedUserIds = [];
      bloc = AuthBloc(
        authRepository: MockAuthRepository(preferences: preferences),
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
  });
}
