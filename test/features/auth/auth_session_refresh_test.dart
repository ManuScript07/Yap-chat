import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';

const _a = AuthSession(userId: 'account-a', displayName: 'Original');
const _changedA = AuthSession(userId: 'account-a', displayName: 'Changed');
const _b = AuthSession(userId: 'account-b');

UserProfile _profile(String userId) => UserProfile(
  id: userId,
  username: 'test_user',
  displayName: 'Profile name',
  birthDate: DateTime.utc(2000, 1, 1),
  onboardingCompleted: true,
  termsAcceptedAt: DateTime.utc(2026, 1, 1),
  privacyAcceptedAt: DateTime.utc(2026, 1, 1),
);

class _Auth implements IAuthRepository {
  AuthSession? session = _a;
  final events = StreamController<AuthSession?>.broadcast();
  final cached = <String, AuthAccountAccess>{};
  int accessChecks = 0;
  Future<AuthAccountAccess> Function() access = () async =>
      const AuthAccountAccess(isBanned: false);
  @override
  AuthSession? get currentSession => session;
  @override
  bool get isSignInCallbackProcessing => false;
  @override
  Stream<AuthSession?> observeSession() => events.stream;
  @override
  Future<AuthAccountAccess> getAccountAccess() {
    accessChecks++;
    return access();
  }

  @override
  Future<AuthAccountAccess?> getCachedAccountAccess(String userId) async =>
      cached[userId];
  @override
  Future<void> cacheAccountAccess(
    String userId,
    AuthAccountAccess access,
  ) async {
    cached[userId] = access;
  }

  void send(AuthSession? value) {
    session = value;
    events.add(value);
  }

  @override
  Future<void> signOut({bool preserveAccountAccess = false}) async =>
      send(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements IProfileRepository {
  int cacheReads = 0;
  int fetches = 0;
  Future<UserProfile?> Function(String) readCache = (id) async => _profile(id);
  Future<UserProfile> Function(AuthSession) fetch = (session) async =>
      _profile(session.userId);
  @override
  Future<UserProfile?> getCachedProfile(String userId) {
    cacheReads++;
    return readCache(userId);
  }

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) {
    fetches++;
    return fetch(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: AuthGateRoute.name,
      path: '/',
      initial: true,
      builder: (_, _) => const AuthGatePage(),
      children: [
        NamedRouteDef(
          name: SplashRoute.name,
          path: '',
          initial: true,
          builder: (_, _) => const Scaffold(body: Text('splash')),
        ),
        NamedRouteDef(
          name: MainRoute.name,
          path: 'app',
          builder: (_, _) => const Scaffold(body: Text('main')),
        ),
        NamedRouteDef(
          name: 'OpenDetail',
          path: 'detail',
          builder: (_, _) => const Scaffold(body: Text('open-detail')),
        ),
        NamedRouteDef(
          name: WelcomeRoute.name,
          path: 'welcome',
          builder: (_, _) => const Scaffold(body: Text('welcome')),
        ),
        NamedRouteDef(
          name: BannedAccountRoute.name,
          path: 'restricted',
          builder: (_, _) => const Scaffold(body: Text('restricted')),
        ),
      ],
    ),
  ];
}

void main() {
  late _Auth auth;
  late _Profiles profiles;
  late AccountSessionController sessionController;
  late AuthBloc bloc;
  late List<AuthStatus> statuses;
  late StreamSubscription<AuthState> states;

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<AuthState> waitFor(bool Function(AuthState) predicate) =>
      bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 5));
  Future<void> start() async {
    final ready = waitFor((state) => state.status == AuthStatus.authenticated);
    bloc.add(const AuthStarted());
    await ready;
    await flush();
    statuses.clear();
  }

  setUp(() {
    auth = _Auth();
    profiles = _Profiles();
    sessionController = AccountSessionController(initialUserId: _a.userId);
    bloc = AuthBloc(
      authRepository: auth,
      profileRepository: profiles,
      accountSessionController: sessionController,
    );
    statuses = [];
    states = bloc.stream.listen((state) => statuses.add(state.status));
  });
  tearDown(() async {
    await states.cancel();
    await bloc.close();
    await auth.events.close();
  });

  test(
    'duplicates do not reload profile, check access, or invalidate account',
    () async {
      await start();
      final snapshot = sessionController.capture();
      auth.send(_a);
      await flush();
      bloc.add(const AuthSessionChanged(_a));
      await flush();
      expect(statuses, isEmpty);
      expect(profiles.cacheReads, 1);
      expect(profiles.fetches, 1);
      expect(auth.accessChecks, 1);
      expect(sessionController.isCurrent(snapshot), isTrue);
    },
  );

  test(
    'changed metadata keeps ready profile while access is checked',
    () async {
      await start();
      final held = Completer<AuthAccountAccess>();
      auth.access = () => held.future;
      auth.send(_changedA);
      await flush();
      expect(bloc.state.status, AuthStatus.authenticated);
      expect(bloc.state.session, _changedA);
      expect(bloc.state.profile, isNotNull);
      expect(statuses, isNot(contains(AuthStatus.loading)));
      held.complete(const AuthAccountAccess(isBanned: false));
      await flush();
      expect(auth.accessChecks, 2);
      expect(profiles.fetches, 2);
      expect(profiles.cacheReads, 1);
    },
  );

  test(
    'background network errors preserve the latest in-memory edited profile',
    () async {
      await start();
      final edited = bloc.state.profile!.copyWith(
        displayName: 'Locally edited',
      );
      bloc.add(AuthProfileUpdated(edited));
      await flush();
      profiles.fetch = (_) async => throw StateError('offline');
      auth.access = () async => throw StateError('offline');
      auth.send(_changedA);
      await flush();
      expect(bloc.state.profile, edited);
      expect(bloc.state.status, AuthStatus.authenticated);
      expect(bloc.state.failure, isNull);
      expect(statuses, isNot(contains(AuthStatus.loading)));
    },
  );

  for (final pendingDeletion in [false, true]) {
    final restriction = pendingDeletion
        ? AuthStatus.deletionPending
        : AuthStatus.banned;
    test('background access confirmation still enforces $restriction', () async {
      await start();
      auth.access = () async => AuthAccountAccess(
        isBanned: !pendingDeletion,
        isDeletionPending: pendingDeletion,
      );
      final restricted = waitFor((state) => state.status == restriction);
      auth.send(_changedA);
      await restricted;
      expect(bloc.state.profile, isNull);
      expect(sessionController.userId, isNull);
      expect(profiles.fetches, 1);
      // Revalidation of a restricted account must not take the duplicate shortcut.
      auth.access = () async => const AuthAccountAccess(isBanned: false);
      final ready = waitFor(
        (state) => state.status == AuthStatus.authenticated,
      );
      bloc.add(const AuthSessionChanged(_changedA));
      await ready;
      await flush();
      expect(sessionController.userId, _a.userId);
    });

    test('profile RPC rejection still enforces $restriction', () async {
      await start();
      profiles.fetch = (_) async => throw StateError(
        pendingDeletion
            ? 'account_pending_deletion'
            : 'account_globally_banned',
      );
      final restricted = waitFor((state) => state.status == restriction);
      auth.send(_changedA);
      await restricted;
      expect(bloc.state.profile, isNull);
      expect(sessionController.userId, isNull);
    });
  }

  test('account change hides A until B cache is loaded', () async {
    await start();
    final held = Completer<UserProfile?>();
    profiles.readCache = (id) =>
        id == _b.userId ? held.future : Future.value(_profile(id));
    auth.send(_b);
    await flush();
    expect(bloc.state.status, AuthStatus.loading);
    expect(bloc.state.profile, isNull);
    expect(sessionController.userId, _b.userId);
    final ready = waitFor((state) => state.status == AuthStatus.authenticated);
    held.complete(_profile(_b.userId));
    await ready;
    await flush();
    expect(bloc.state.profile?.id, _b.userId);
  });

  test(
    'stale background restriction for A cannot invalidate switched account B',
    () async {
      await start();
      final held = Completer<AuthAccountAccess>();
      auth.access = () => held.future;
      auth.send(_changedA);
      await flush();
      auth.access = () async => const AuthAccountAccess(isBanned: false);
      final readyB = waitFor(
        (state) =>
            state.status == AuthStatus.authenticated &&
            state.profile?.id == _b.userId,
      );
      auth.send(_b);
      await readyB;
      held.complete(const AuthAccountAccess(isBanned: true));
      await flush();
      expect(bloc.state.profile?.id, _b.userId);
      expect(bloc.state.status, AuthStatus.authenticated);
      expect(sessionController.userId, _b.userId);
    },
  );

  test(
    'sign-out during background validation cannot restore the old session',
    () async {
      await start();
      final held = Completer<AuthAccountAccess>();
      auth.access = () => held.future;
      auth.send(_changedA);
      await flush();
      final loggedOut = waitFor(
        (state) => state.status == AuthStatus.unauthenticated,
      );
      bloc.add(const AuthSignOutRequested());
      await loggedOut;
      held.complete(const AuthAccountAccess(isBanned: false));
      await flush();
      expect(bloc.state.profile, isNull);
      expect(bloc.state.session, isNull);
      expect(sessionController.userId, isNull);
    },
  );

  test('explicit startup retry still validates the same account', () async {
    await start();
    bloc.add(const AuthRetryRequested());
    await flush();
    expect(statuses, contains(AuthStatus.loading));
    expect(auth.accessChecks, 2);
    expect(profiles.fetches, 2);
  });

  test('cold startup still opens the cached profile without network', () async {
    auth.access = () async => throw StateError('offline');
    profiles.fetch = (_) async => throw StateError('offline');
    await start();
    expect(bloc.state.status, AuthStatus.authenticated);
    expect(bloc.state.profile?.id, _a.userId);
    expect(bloc.state.failure, isNull);
  });

  for (final pendingDeletion in [false, true]) {
    final restriction = pendingDeletion
        ? AuthStatus.deletionPending
        : AuthStatus.banned;
    test('cold startup preserves cached $restriction while offline', () async {
      auth.cached[_a.userId] = AuthAccountAccess(
        isBanned: !pendingDeletion,
        isDeletionPending: pendingDeletion,
        deletionScheduledFor: pendingDeletion
            ? DateTime.now().toUtc().subtract(const Duration(minutes: 1))
            : null,
      );
      auth.access = () async => throw StateError('offline');
      final restricted = waitFor((state) => state.status == restriction);
      bloc.add(const AuthStarted());
      await restricted;
      await flush();
      expect(bloc.state.profile, isNull);
      expect(sessionController.userId, isNull);
      expect(profiles.fetches, 0);
      if (pendingDeletion) expect(bloc.state.isDeletionExpired, isTrue);
    });
  }

  Future<StackRouter> openDetail(WidgetTester tester, _Router router) async {
    await tester.runAsync(start);
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp.router(routerConfig: router.config()),
      ),
    );
    await tester.pumpAndSettle();
    final gate = router.innerRouterOf<StackRouter>(AuthGateRoute.name)!;
    unawaited(gate.push(const PageRouteInfo('OpenDetail')));
    await tester.pumpAndSettle();
    expect(find.text('open-detail'), findsOneWidget);
    return gate;
  }

  testWidgets(
    'duplicate and slow metadata refresh preserve the actual navigation stack',
    (tester) async {
      final router = _Router();
      final gate = await openDetail(tester, router);
      final oldStack = gate.stackData.toList();
      auth.send(_a);
      await tester.runAsync(flush);
      await tester.pumpAndSettle();
      expect(find.text('open-detail'), findsOneWidget);
      final held = Completer<AuthAccountAccess>();
      auth.access = () => held.future;
      auth.send(_changedA);
      await tester.runAsync(flush);
      await tester.pumpAndSettle();
      expect(find.text('splash'), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
      expect(gate.stackData, orderedEquals(oldStack));
      held.complete(const AuthAccountAccess(isBanned: false));
      await tester.runAsync(flush);
      await tester.pumpAndSettle();
      expect(gate.stackData, orderedEquals(oldStack));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets('confirmed ban removes the previously open detail', (
    tester,
  ) async {
    final router = _Router();
    await openDetail(tester, router);
    auth.access = () async => const AuthAccountAccess(isBanned: true);
    await tester.runAsync(() async {
      final restricted = waitFor((state) => state.status == AuthStatus.banned);
      auth.send(_changedA);
      await restricted;
    });
    await tester.pumpAndSettle();
    expect(find.text('restricted'), findsOneWidget);
    expect(find.text('open-detail'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets(
    'switching account replaces the previously open detail with main',
    (tester) async {
      final router = _Router();
      await openDetail(tester, router);
      await tester.runAsync(() async {
        final ready = waitFor(
          (state) =>
              state.status == AuthStatus.authenticated &&
              state.profile?.id == _b.userId,
        );
        auth.send(_b);
        await ready;
      });
      await tester.pumpAndSettle();
      expect(find.text('main'), findsOneWidget);
      expect(find.text('open-detail'), findsNothing);
      expect(bloc.state.profile?.id, _b.userId);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
