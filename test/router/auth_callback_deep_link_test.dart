import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.dart';

const _authRedirectUrl = 'yapchat://login-callback/';
final _callbackUri = Uri.parse(
  'yapchat://login-callback/'
  '?auth_attempt=stale-attempt&code=authorization-code',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _IdleAuthRepository authRepository;
  late AuthBloc authBloc;

  setUp(() async {
    authRepository = _IdleAuthRepository();
    authBloc = AuthBloc(
      authRepository: authRepository,
      profileRepository: _UnusedProfileRepository(),
    );

    final unauthenticated = authBloc.stream.firstWhere(
      (state) => state.status == AuthStatus.unauthenticated,
    );
    authBloc.add(const AuthStarted());
    await unauthenticated;
  });

  tearDown(() async {
    await authBloc.close();
    await authRepository.close();
  });

  testWidgets('a runtime auth callback does not push Splash over Welcome', (
    tester,
  ) async {
    final router = AppRouter();
    addTearDown(router.dispose);
    final routerConfig = router.config(
      deepLinkBuilder: (deepLink) =>
          resolveAppDeepLink(deepLink, authRedirectUrl: _authRedirectUrl),
    );

    await tester.pumpWidget(_buildTestApp(authBloc, routerConfig));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);

    final callbackState = await routerConfig.routeInformationParser!
        .parseRouteInformation(RouteInformation(uri: _callbackUri));
    await routerConfig.routerDelegate.setNewRoutePath(callbackState);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing);
  });

  testWidgets('a cold-start auth callback still opens the default auth gate', (
    tester,
  ) async {
    final router = AppRouter();
    addTearDown(router.dispose);
    final routerConfig = router.config(
      deepLinkBuilder: (deepLink) =>
          resolveAppDeepLink(deepLink, authRedirectUrl: _authRedirectUrl),
    );
    final callbackState = await routerConfig.routeInformationParser!
        .parseRouteInformation(RouteInformation(uri: _callbackUri));

    await routerConfig.routerDelegate.setInitialRoutePath(callbackState);
    await tester.pumpWidget(_buildTestApp(authBloc, routerConfig));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing);
  });
}

Widget _buildTestApp(AuthBloc authBloc, RouterConfig<Object> routerConfig) {
  return BlocProvider<AuthBloc>.value(
    value: authBloc,
    child: MaterialApp.router(
      locale: const Locale('ru'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: routerConfig,
    ),
  );
}

final class _IdleAuthRepository implements IAuthRepository {
  final _sessions = StreamController<AuthSession?>.broadcast();

  @override
  AuthSession? get currentSession => null;

  @override
  bool get isSignInCallbackProcessing => false;

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
  Future<void> signInWithYandex() async {}

  @override
  Future<void> cancelPendingSignIn() async {}

  @override
  Future<DateTime?> requestAccountDeletion(AccountDeletionSurvey survey) async => null;

  @override
  Future<void> restoreAccountDeletion() async {}

  @override
  Future<void> signOut({bool preserveAccountAccess = false}) async {}

  Future<void> close() => _sessions.close();
}

final class _UnusedProfileRepository implements IProfileRepository {
  @override
  Future<UserProfile?> getCachedProfile(String userId) async => null;

  @override
  Future<String?> resolveSharedProfileUsername(String username) async => null;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) => throw UnimplementedError();
}
